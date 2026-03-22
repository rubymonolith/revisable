# frozen_string_literal: true

module Revisable
  module Renderers
    class TextRenderer
      attr_reader :field_diff

      def initialize(field_diff)
        @field_diff = field_diff
      end

      def render
        return nil unless field_diff.changed?

        lines = []
        lines << "--- a/#{field_diff.field_name}"
        lines << "+++ b/#{field_diff.field_name}"

        field_diff.hunks.each do |change|
          case change.action
          when "="
            lines << " #{change.old_element}"
          when "!"
            lines << "-#{change.old_element}"
            lines << "+#{change.new_element}"
          when "-"
            lines << "-#{change.old_element}"
          when "+"
            lines << "+#{change.new_element}"
          end
        end

        lines.join("\n")
      end
    end
  end
end
