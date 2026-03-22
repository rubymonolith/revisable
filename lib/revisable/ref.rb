# frozen_string_literal: true

module Revisable
  class Ref < ActiveRecord::Base
    self.table_name = "revisable_refs"

    belongs_to :versionable, polymorphic: true

    belongs_to :commit,
      class_name: "Revisable::Commit",
      foreign_key: :commit_sha,
      primary_key: :sha

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

    def advance!(new_sha, expected_sha: nil)
      if expected_sha
        rows = self.class.where(id: id, commit_sha: expected_sha).update_all(commit_sha: new_sha)
        raise StaleRefError, "Ref #{name} was updated by another process" if rows == 0
        self.commit_sha = new_sha
      else
        update!(commit_sha: new_sha)
      end
    end
  end
end
