# frozen_string_literal: true

module Revisable
  module ActiveRecord
    module ControllerHelpers
      extend ActiveSupport::Concern

      included do
        around_action :revisable_set_author, if: :revisable_author
      end

      private

      def revisable_set_author(&block)
        Revisable::CurrentAuthor.with(revisable_author, &block)
      end

      # Override in your controller to provide the current user
      # Example:
      #   def revisable_author
      #     current_user
      #   end
      def revisable_author
        nil
      end
    end
  end
end
