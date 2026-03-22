# frozen_string_literal: true

module Revisable
  class FieldDiff
    attr_reader :field_name, :status, :a, :b

    def initialize(field_name:, blob_a:, blob_b:)
      @field_name = field_name.to_sym
      @a = blob_a&.data
      @b = blob_b&.data

      @status = if blob_a.nil? && blob_b.nil?
        :unchanged
      elsif blob_a.nil?
        :added
      elsif blob_b.nil?
        :removed
      elsif blob_a.sha == blob_b.sha
        :unchanged
      else
        :modified
      end
    end

    def changed?
      status != :unchanged
    end

    def hunks
      @hunks ||= changed? ? ::Diff::LCS.sdiff(lines_a, lines_b) : []
    end

    def to_text
      Renderers::TextRenderer.new(self).render
    end

    def to_html
      Renderers::HtmlRenderer.new(self).render
    end

    private

    def lines_a
      @lines_a ||= (@a || "").lines(chomp: true)
    end

    def lines_b
      @lines_b ||= (@b || "").lines(chomp: true)
    end
  end
end
