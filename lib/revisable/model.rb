# frozen_string_literal: true

module Revisable
  module Model
    extend ActiveSupport::Concern

    included do
      after_create :revisable_initial_commit, if: :revisable_has_content?
      after_update :revisable_auto_commit, if: :revisable_fields_changed?
    end

    class_methods do
      def revisable(*fields, auto_commit: true)
        @revisable_fields = fields.map(&:to_sym)
        @revisable_auto_commit = auto_commit
      end

      def revisable_fields
        @revisable_fields || []
      end

      def revisable_auto_commit?
        @revisable_auto_commit != false
      end
    end

    def repository
      @_revisable_repository ||= Repository.new(
        versionable: self,
        fields: self.class.revisable_fields
      )
    end

    private

    def revisable_has_content?
      self.class.revisable_auto_commit? &&
        self.class.revisable_fields.any? { |f| send(f).present? }
    end

    def revisable_fields_changed?
      self.class.revisable_auto_commit? &&
        (saved_changes.keys.map(&:to_sym) & self.class.revisable_fields).any?
    end

    def revisable_changed_fields
      self.class.revisable_fields.each_with_object({}) do |field, hash|
        hash[field] = send(field)
      end
    end

    def revisable_initial_commit
      repository.commit!(
        message: "Initial version",
        author: CurrentAuthor.get,
        fields: revisable_changed_fields
      )
    end

    def revisable_auto_commit
      changed = saved_changes.keys.map(&:to_sym) & self.class.revisable_fields
      message = "Updated #{changed.map(&:to_s).join(', ')}"

      repository.commit!(
        message: message,
        author: CurrentAuthor.get,
        fields: revisable_changed_fields
      )
    end
  end
end
