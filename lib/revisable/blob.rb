# frozen_string_literal: true

require "digest/sha2"

module Revisable
  class Blob < ActiveRecord::Base
    self.table_name = "revisable_blobs"

    validates :sha, presence: true, uniqueness: true
    validates :data, presence: true

    def self.store(content)
      content = content.to_s
      sha = compute_sha(content)

      find_or_create_by!(sha: sha) do |blob|
        blob.data = content
      end
    end

    def self.compute_sha(content)
      Digest::SHA256.hexdigest(content.to_s)
    end
  end
end
