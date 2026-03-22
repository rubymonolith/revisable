# frozen_string_literal: true

module Revisable
  module Renderers
    class HtmlRenderer
      attr_reader :field_diff

      def initialize(field_diff)
        @field_diff = field_diff
      end

      def render
        return nil unless field_diff.changed?

        parts = []
        parts << "<div class=\"revisable-diff\" data-field=\"#{field_diff.field_name}\">"

        field_diff.hunks.each do |change|
          escaped_old = escape_html(change.old_element.to_s)
          escaped_new = escape_html(change.new_element.to_s)

          case change.action
          when "="
            parts << "<span class=\"unchanged\">#{escaped_old}</span>"
          when "!"
            parts << "<del>#{escaped_old}</del>"
            parts << "<ins>#{escaped_new}</ins>"
          when "-"
            parts << "<del>#{escaped_old}</del>"
          when "+"
            parts << "<ins>#{escaped_new}</ins>"
          end
        end

        parts << "</div>"
        parts.join("\n")
      end

      private

      def escape_html(str)
        str.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
      end
    end
  end
end
