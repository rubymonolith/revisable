# frozen_string_literal: true

module Revisable
  class CommitField < ActiveRecord::Base
    self.table_name = "revisable_commit_fields"

    belongs_to :commit,
      class_name: "Revisable::Commit",
      foreign_key: :commit_sha,
      primary_key: :sha

    belongs_to :blob,
      class_name: "Revisable::Blob",
      foreign_key: :blob_sha,
      primary_key: :sha

    validates :field_name, presence: true
  end
end
