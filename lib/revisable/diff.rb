# frozen_string_literal: true

module Revisable
  class Diff
    include Enumerable

    attr_reader :commit_a, :commit_b

    def initialize(commit_a:, commit_b:, versionable_fields:)
      @commit_a = commit_a
      @commit_b = commit_b
      @fields_a = commit_a&.field_set || FieldSet.empty
      @fields_b = commit_b&.field_set || FieldSet.empty
      @versionable_fields = versionable_fields

      @fields = build_field_diffs
    end

    def field(name)
      @fields[name.to_sym]
    end

    def each(&block)
      @fields.each(&block)
    end

    def changed?
      @fields.values.any?(&:changed?)
    end

    def changed_fields
      @fields.values.select(&:changed?)
    end

    def to_text
      @fields.values
        .select(&:changed?)
        .map(&:to_text)
        .join("\n\n")
    end

    def to_html
      @fields.values
        .select(&:changed?)
        .map(&:to_html)
        .join("\n")
    end

    private

    def build_field_diffs
      @versionable_fields.each_with_object({}) do |field, hash|
        field = field.to_sym
        hash[field] = FieldDiff.new(
          field_name: field,
          blob_a: @fields_a[field],
          blob_b: @fields_b[field]
        )
      end
    end
  end
end
