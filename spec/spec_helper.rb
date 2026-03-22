# frozen_string_literal: true

require "revisable"
require "active_record"

# Set up in-memory SQLite database
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :revisable_blobs do |t|
    t.string :sha, null: false, index: { unique: true }
    t.text :data, null: false
    t.integer :size, null: false
    t.timestamps
  end

  create_table :revisable_commits do |t|
    t.string :sha, null: false, index: { unique: true }
    t.string :versionable_type, null: false
    t.bigint :versionable_id, null: false
    t.string :author_type
    t.bigint :author_id
    t.string :message, null: false
    t.datetime :committed_at, null: false
    t.timestamps
  end

  add_index :revisable_commits, [:versionable_type, :versionable_id]

  create_table :revisable_commit_parents do |t|
    t.string :commit_sha, null: false
    t.string :parent_sha, null: false
    t.integer :position, null: false, default: 0
  end

  add_index :revisable_commit_parents, :commit_sha
  add_index :revisable_commit_parents, :parent_sha

  create_table :revisable_commit_fields do |t|
    t.string :commit_sha, null: false
    t.string :field_name, null: false
    t.string :blob_sha, null: false
  end

  add_index :revisable_commit_fields, :commit_sha
  add_index :revisable_commit_fields, [:commit_sha, :field_name], unique: true

  create_table :revisable_refs do |t|
    t.string :versionable_type, null: false
    t.bigint :versionable_id, null: false
    t.string :name, null: false
    t.string :ref_type, null: false
    t.string :commit_sha, null: false
    t.string :message
    t.timestamps
  end

  add_index :revisable_refs, [:versionable_type, :versionable_id, :ref_type, :name],
            unique: true, name: "index_revisable_refs_unique"

  # Test models
  create_table :posts do |t|
    t.string :title
    t.text :body
    t.timestamps
  end

  create_table :users do |t|
    t.string :name
    t.timestamps
  end
end

# Test model
class Post < ActiveRecord::Base
  include Revisable::Model
  revisable :title, :body
end

class User < ActiveRecord::Base
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:each) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
