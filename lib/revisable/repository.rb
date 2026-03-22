# frozen_string_literal: true

module Revisable
  class Repository
    attr_reader :versionable, :versionable_fields

    def initialize(versionable:, fields:)
      @versionable = versionable
      @versionable_fields = fields.map(&:to_sym)
    end

    # --- Commits ---

    def commit!(branch: "main", author: nil, message:, fields:, parent_shas: nil)
      timestamp = Time.current

      # Resolve parent(s)
      if parent_shas.nil?
        ref = find_ref(branch, type: "branch") if branch
        parent_commit = ref&.commit
        parent_shas = parent_commit ? [parent_commit.sha] : []
      end

      # Build full field set: start from parent, overlay changes
      parent_field_set = parent_shas.any? ? Commit.find_by!(sha: parent_shas.first).field_set : FieldSet.empty
      blob_shas = {}

      versionable_fields.each do |field|
        if fields.key?(field)
          blob = Blob.store(fields[field])
          blob_shas[field] = blob.sha
        elsif parent_field_set[field]
          blob_shas[field] = parent_field_set.sha_for(field)
        else
          blob = Blob.store("")
          blob_shas[field] = blob.sha
        end
      end

      # Compute commit SHA
      sha = Commit.build_sha(
        parent_shas: parent_shas,
        field_blobs: blob_shas,
        message: message,
        timestamp: timestamp
      )

      # Create commit
      commit = Commit.create!(
        sha: sha,
        versionable: versionable,
        author: author,
        message: message,
        committed_at: timestamp
      )

      # Link parents
      parent_shas.each_with_index do |parent_sha, i|
        CommitParent.create!(commit_sha: sha, parent_sha: parent_sha, position: i)
      end

      # Create commit fields
      blob_shas.each do |field, blob_sha|
        CommitField.create!(commit_sha: sha, field_name: field.to_s, blob_sha: blob_sha)
      end

      # Advance branch ref
      if branch
        ref = find_ref(branch, type: "branch")
        if ref
          ref.advance!(sha)
        else
          Ref.create!(
            versionable: versionable,
            name: branch,
            ref_type: "branch",
            commit_sha: sha
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
        commit_sha: source_ref.commit_sha
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
        commit_sha: source.commit_sha,
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
      versionable.update!(attrs)
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
      # Try as ref first (branch or tag)
      ref = find_ref(ref_or_sha)
      return ref.commit if ref

      # Try as SHA
      commit = commits_scope.find_by(sha: ref_or_sha)
      return commit if commit

      # Try as SHA prefix
      commit = commits_scope.where("sha LIKE ?", "#{ref_or_sha}%").first
      return commit if commit

      raise RefNotFoundError, "Could not resolve '#{ref_or_sha}'"
    end

    def walk_history(commit, limit: nil)
      result = []
      queue = [commit]
      visited = Set.new

      while queue.any? && (limit.nil? || result.size < limit)
        current = queue.shift
        next if visited.include?(current.sha)
        visited.add(current.sha)

        result << current

        current.parents.order(committed_at: :desc).each do |parent|
          queue << parent unless visited.include?(parent.sha)
        end
      end

      result
    end

    def find_common_ancestor(commit_a, commit_b)
      ancestors_a = collect_ancestors(commit_a)
      ancestors_b = collect_ancestors(commit_b)
      common = ancestors_a & ancestors_b
      return nil if common.empty?

      # Return the most recent common ancestor
      commits_scope.where(sha: common.to_a).order(committed_at: :desc).first
    end

    def collect_ancestors(commit)
      ancestors = Set.new
      queue = [commit]

      while queue.any?
        current = queue.shift
        next if ancestors.include?(current.sha)
        ancestors.add(current.sha)
        current.parents.each { |p| queue << p }
      end

      ancestors
    end
  end
end
