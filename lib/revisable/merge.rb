# frozen_string_literal: true

module Revisable
  class Merge
    include Enumerable

    attr_reader :into_commit, :from_commit, :ancestor_commit,
                :into, :from

    def initialize(into_commit:, from_commit:, ancestor_commit:,
                   into:, from:, versionable_fields:)
      @into_commit = into_commit
      @from_commit = from_commit
      @ancestor_commit = ancestor_commit
      @into = into.to_s
      @from = from.to_s
      @versionable_fields = versionable_fields

      @into_fields = into_commit.field_set
      @from_fields = from_commit.field_set
      @ancestor_fields = ancestor_commit&.field_set || FieldSet.empty

      @fields = build_merge_fields
    end

    def field(name)
      @fields[name.to_sym]
    end

    def each(&block)
      @fields.each(&block)
    end

    def clean?
      conflicts.empty?
    end

    def conflicts
      @fields.values.select(&:conflicted?)
    end

    def auto_resolved
      @fields.values.select(&:auto_resolved?)
    end

    def unchanged
      @fields.values.select(&:unchanged?)
    end

    def resolve(field_name, value)
      f = field(field_name)
      raise Error, "Unknown field: #{field_name}" unless f
      f.resolve(value)
    end

    def resolved?(field_name)
      field(field_name)&.resolved? || false
    end

    def all_resolved?
      @fields.values.none?(&:conflicted?)
    end

    def unresolved
      @fields.values.select(&:conflicted?)
    end

    def commit!(repository:, author: nil, message: "Merge #{from} into #{into}")
      raise UnresolvedConflictsError, "Unresolved conflicts: #{unresolved.map(&:field_name).join(', ')}" unless all_resolved?

      fields = @fields.each_with_object({}) do |(name, merge_field), hash|
        hash[name] = merge_field.value
      end

      repository.commit!(
        branch: nil,
        author: author,
        message: message,
        fields: fields,
        parent_shas: [into_commit.sha, from_commit.sha]
      )
    end

    private

    def build_merge_fields
      @versionable_fields.each_with_object({}) do |field, result|
        field = field.to_sym

        ancestor_sha = @ancestor_fields.sha_for(field)
        into_sha = @into_fields.sha_for(field)
        from_sha = @from_fields.sha_for(field)

        into_data = @into_fields.data_for(field)
        from_data = @from_fields.data_for(field)
        ancestor_data = @ancestor_fields.data_for(field)

        into_changed = into_sha != ancestor_sha
        from_changed = from_sha != ancestor_sha

        status, auto_value = if !into_changed && !from_changed
          [:unchanged, into_data]
        elsif into_changed && !from_changed
          [:auto_resolved, into_data]
        elsif !into_changed && from_changed
          [:auto_resolved, from_data]
        elsif into_sha == from_sha
          [:auto_resolved, into_data]
        else
          [:conflicted, nil]
        end

        result[field] = MergeField.new(
          field_name: field,
          status: status,
          versions: { @into => into_data, @from => from_data },
          ancestor: ancestor_data,
          auto_resolved_value: auto_value
        )
      end
    end
  end
end
