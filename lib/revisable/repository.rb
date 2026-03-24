# frozen_string_literal: true

module Revisable
  class Repository
    attr_reader :versionable, :versionable_fields

    def initialize(versionable:, fields:)
      @versionable = versionable
      @versionable_fields = fields.map(&:to_sym)
    end

    # --- Commits ---

    def commit!(branch: "main", author: nil, message: nil, fields:, parent_shas: nil)
      # Resolve parent(s)
      if parent_shas.nil?
        ref = find_ref(branch, type: "branch") if branch
        parent_commit = ref&.commit
        parent_shas = parent_commit ? [parent_commit.sha] : []
      end

      # Look up parent commits by SHA to get their IDs
      parent_commits = parent_shas.map { |sha| Commit.find_by!(sha: sha) }

      # Build full field set: start from parent, overlay changes
      parent_field_set = parent_commits.any? ? parent_commits.first.field_set : FieldSet.empty
      blob_map = {}

      versionable_fields.each do |field|
        if fields.key?(field)
          blob_map[field] = Blob.store(fields[field])
        elsif parent_field_set[field]
          blob_map[field] = parent_field_set[field]
        else
          blob_map[field] = Blob.store("")
        end
      end

      # Compute commit SHA
      blob_shas = blob_map.transform_values(&:sha)
      sha = Commit.build_sha(
        parent_shas: parent_shas,
        field_blobs: blob_shas,
        message: message
      )

      # Create commit
      commit = Commit.create!(
        sha: sha,
        versionable: versionable,
        author: author,
        message: message
      )

      # Bulk insert parents
      if parent_commits.any?
        parent_records = parent_commits.each_with_index.map do |parent, i|
          { commit_id: commit.id, parent_id: parent.id, position: i }
        end
        CommitParent.insert_all(parent_records)
      end

      # Bulk insert commit fields
      field_records = blob_map.map do |field, blob|
        { commit_id: commit.id, field_name: field.to_s, blob_id: blob.id }
      end
      CommitField.insert_all(field_records)

      # Advance branch ref
      if branch
        ref = find_ref(branch, type: "branch")
        if ref
          ref.advance!(commit.id)
        else
          Ref.create!(
            versionable: versionable,
            name: branch,
            ref_type: "branch",
            commit_id: commit.id
          )
        end
      end

      commit
    end

    # --- Branches ---

    def branch!(name, from: "main")
      source_ref = find_ref!(from)
      ref = Ref.create!(
        versionable: versionable,
        name: name,
        ref_type: "branch",
        commit_id: source_ref.commit_id
      )
      Branch.new(ref)
    end

    def branches
      refs_scope.branches.map { |ref| Branch.new(ref) }
    end

    # --- Tags ---

    def tag!(name, ref: "main", message: nil)
      source = find_ref!(ref)
      ref = Ref.create!(
        versionable: versionable,
        name: name,
        ref_type: "tag",
        commit_id: source.commit_id,
        message: message
      )
      Tag.new(ref)
    end

    def tags
      refs_scope.tags.map { |ref| Tag.new(ref) }
    end

    # --- Reading ---

    def at(ref_or_sha)
      commit = resolve_commit(ref_or_sha)
      Snapshot.new(commit: commit, fields: versionable_fields)
    end

    def log(ref = "main", limit: nil)
      commit = resolve_commit(ref)
      commits = walk_history(commit, limit: limit)
      Log.new(commits)
    end

    # --- Diffing ---

    def diff(ref_a, ref_b)
      commit_a = resolve_commit(ref_a)
      commit_b = resolve_commit(ref_b)

      Diff.new(
        commit_a: commit_a,
        commit_b: commit_b,
        versionable_fields: versionable_fields
      )
    end

    # --- Merging ---

    def merge(from_ref, into: "main")
      into_commit = resolve_commit(into)
      from_commit = resolve_commit(from_ref)
      ancestor_commit = find_common_ancestor(into_commit, from_commit)

      Merge.new(
        into_commit: into_commit,
        from_commit: from_commit,
        ancestor_commit: ancestor_commit,
        into: into,
        from: from_ref,
        versionable_fields: versionable_fields
      )
    end

    # --- Publishing ---

    def publish!(ref = nil)
      ref ||= refs_scope.tags.order(created_at: :desc).first&.name
      raise RefNotFoundError, "No tags found" unless ref

      snapshot = at(ref)
      attrs = snapshot.to_h

      versionable.instance_variable_set(:@revisable_skip_auto_commit, true)
      versionable.update!(attrs)
    ensure
      versionable.instance_variable_set(:@revisable_skip_auto_commit, false)
    end

    private

    def refs_scope
      Ref.where(versionable_type: versionable.class.name, versionable_id: versionable.id)
    end

    def commits_scope
      Commit.where(versionable_type: versionable.class.name, versionable_id: versionable.id)
    end

    def find_ref(name, type: nil)
      scope = refs_scope.where(name: name)
      scope = scope.where(ref_type: type) if type
      scope.first
    end

    def find_ref!(name, type: nil)
      find_ref(name, type: type) || raise(RefNotFoundError, "Ref '#{name}' not found")
    end

    def resolve_commit(ref_or_sha)
      ref = find_ref(ref_or_sha)
      return ref.commit if ref

      commit = commits_scope.find_by(sha: ref_or_sha)
      return commit if commit

      commit = commits_scope.where("sha LIKE ?", "#{ref_or_sha}%").first
      return commit if commit

      raise RefNotFoundError, "Could not resolve '#{ref_or_sha}'"
    end

    # Walk commit history using a recursive CTE — single query instead of N+1
    def walk_history(commit, limit: nil)
      sql = <<~SQL
        WITH RECURSIVE history(id) AS (
          SELECT id FROM revisable_commits WHERE id = ?
          UNION ALL
          SELECT cp.parent_id
          FROM revisable_commit_parents cp
          INNER JOIN history h ON h.id = cp.commit_id
        )
        SELECT revisable_commits.*
        FROM revisable_commits
        INNER JOIN history ON history.id = revisable_commits.id
        WHERE revisable_commits.versionable_type = ?
          AND revisable_commits.versionable_id = ?
        ORDER BY revisable_commits.created_at DESC
      SQL

      sql += " LIMIT #{limit.to_i}" if limit

      Commit.find_by_sql([sql, commit.id, versionable.class.name, versionable.id])
    end

    # Find common ancestor using two recursive CTEs
    def find_common_ancestor(commit_a, commit_b)
      sql = <<~SQL
        WITH RECURSIVE
        ancestors_a(id) AS (
          SELECT id FROM revisable_commits WHERE id = ?
          UNION ALL
          SELECT cp.parent_id
          FROM revisable_commit_parents cp
          INNER JOIN ancestors_a a ON a.id = cp.commit_id
        ),
        ancestors_b(id) AS (
          SELECT id FROM revisable_commits WHERE id = ?
          UNION ALL
          SELECT cp.parent_id
          FROM revisable_commit_parents cp
          INNER JOIN ancestors_b b ON b.id = cp.commit_id
        )
        SELECT revisable_commits.*
        FROM revisable_commits
        WHERE id IN (SELECT id FROM ancestors_a INTERSECT SELECT id FROM ancestors_b)
        ORDER BY revisable_commits.created_at DESC
        LIMIT 1
      SQL

      Commit.find_by_sql([sql, commit_a.id, commit_b.id]).first
    end
  end
end
