# frozen_string_literal: true

module Revisable
  class Ref < ActiveRecord::Base
    self.table_name = "revisable_refs"

    belongs_to :versionable, polymorphic: true

    belongs_to :commit,
      class_name: "Revisable::Commit",
      foreign_key: :commit_id

    validates :name, presence: true
    validates :ref_type, presence: true, inclusion: { in: %w[branch tag] }
    validates :name, uniqueness: { scope: [:versionable_type, :versionable_id, :ref_type] }

    scope :branches, -> { where(ref_type: "branch") }
    scope :tags, -> { where(ref_type: "tag") }

    def branch?
      ref_type == "branch"
    end

    def tag?
      ref_type == "tag"
    end

    def advance!(new_commit_id, expected_commit_id: nil)
      if expected_commit_id
        rows = self.class.where(id: id, commit_id: expected_commit_id).update_all(commit_id: new_commit_id)
        raise StaleRefError, "Ref #{name} was updated by another process" if rows == 0
        self.commit_id = new_commit_id
      else
        update!(commit_id: new_commit_id)
      end
    end
  end
end
