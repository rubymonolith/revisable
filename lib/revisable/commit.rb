# frozen_string_literal: true

require "digest/sha2"

module Revisable
  class Commit < ActiveRecord::Base
    self.table_name = "revisable_commits"

    belongs_to :versionable, polymorphic: true
    belongs_to :author, polymorphic: true, optional: true

    has_many :commit_fields,
      class_name: "Revisable::CommitField",
      foreign_key: :commit_sha,
      primary_key: :sha,
      dependent: :destroy

    has_many :parent_links,
      class_name: "Revisable::CommitParent",
      foreign_key: :commit_sha,
      primary_key: :sha,
      dependent: :destroy

    validates :sha, presence: true, uniqueness: true
    validates :message, presence: true

    def parents
      Commit.where(sha: parent_links.order(:position).pluck(:parent_sha))
    end

    def parent_shas
      parent_links.order(:position).pluck(:parent_sha)
    end

    def root?
      parent_links.empty?
    end

    def merge?
      parent_links.count > 1
    end

    def snapshot(fields:)
      Snapshot.new(commit: self, fields: fields)
    end

    def field_set
      @field_set ||= begin
        blobs = commit_fields.includes(:blob).each_with_object({}) do |cf, hash|
          hash[cf.field_name.to_sym] = cf.blob
        end
        FieldSet.new(blobs)
      end
    end

    def self.build_sha(parent_shas:, field_blobs:, message:, timestamp:)
      parts = [
        "parents:#{parent_shas.sort.join(',')}",
        "fields:#{field_blobs.sort.map { |k, v| "#{k}:#{v}" }.join(',')}",
        "message:#{message}",
        "timestamp:#{timestamp.iso8601}"
      ]
      Digest::SHA256.hexdigest(parts.join("\n"))
    end
  end

  class CommitParent < ActiveRecord::Base
    self.table_name = "revisable_commit_parents"

    belongs_to :commit,
      class_name: "Revisable::Commit",
      foreign_key: :commit_sha,
      primary_key: :sha
  end
end
