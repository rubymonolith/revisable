#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "activerecord", "~> 7.0"
  gem "sqlite3"
  gem "revisable", path: File.expand_path("..", __dir__)
  gem "irb"
  gem "rdoc"
end

require "revisable"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil

ActiveRecord::Schema.define do
  create_table(:revisable_blobs) { |t| t.string :sha, null: false, index: { unique: true }; t.text :data, null: false; t.integer :size, null: false; t.timestamps }
  create_table(:revisable_commits) { |t| t.string :sha, null: false, index: { unique: true }; t.string :versionable_type, null: false; t.bigint :versionable_id, null: false; t.string :author_type; t.bigint :author_id; t.string :message, null: false; t.datetime :committed_at, null: false; t.timestamps }
  create_table(:revisable_commit_parents) { |t| t.string :commit_sha, null: false; t.string :parent_sha, null: false; t.integer :position, null: false, default: 0 }
  create_table(:revisable_commit_fields) { |t| t.string :commit_sha, null: false; t.string :field_name, null: false; t.string :blob_sha, null: false }
  add_index :revisable_commit_fields, [:commit_sha, :field_name], unique: true
  create_table(:revisable_refs) { |t| t.string :versionable_type, null: false; t.bigint :versionable_id, null: false; t.string :name, null: false; t.string :ref_type, null: false; t.string :commit_sha, null: false; t.string :message; t.timestamps }
  add_index :revisable_refs, [:versionable_type, :versionable_id, :ref_type, :name], unique: true, name: "idx_refs"
  create_table(:posts) { |t| t.string :title; t.text :body; t.timestamps }
end

class Post < ActiveRecord::Base
  include Revisable::Model
  revisable :title, :body
end

puts "\e[1mRevisable #{Revisable::VERSION} — Interactive Demo\e[0m"
puts "Each step is pre-filled. Edit if you want, then press enter.\n\n"

require "reline"
require "irb"

steps = [
  'post = Post.create!(title: "How to Deploy Rails", body: "# Step 1\nSet up your server")',
  'repo = post.repository',
  'puts repo.log("main").to_text',
  'repo.commit!(message: "Added step 2", fields: { body: "# Step 1\nSet up your server\n\n# Step 2\nInstall Ruby" })',
  'puts repo.log("main").to_text',
  'repo.branch!("rewrite", from: "main")',
  'repo.commit!(branch: "rewrite", message: "Rewrote intro", fields: { title: "Deploying Rails: A Guide", body: "# Introduction\nThis guide covers deployment." })',
  'repo.commit!(message: "Fixed capitalization", fields: { title: "How to Deploy Rails Apps" })',
  'repo.at("main").title',
  'repo.at("rewrite").title',
  'puts repo.diff("main", "rewrite").to_text',
  'merge = repo.merge("rewrite", into: "main")',
  'merge.clean?',
  'merge.conflicts.map(&:field_name)',
  'merge.conflicts.first.version("main")',
  'merge.conflicts.first.version("rewrite")',
  'merge.conflicts.each { |f| f.resolve("rewrite") }',
  'merge.commit!(repository: repo)',
  'repo.at("main").title',
  'repo.tag!("v1", ref: "main")',
  'repo.publish!("v1")',
  'post.reload',
  'post.title',
  'puts repo.log("main").to_text',
]

Reline.pre_input_hook = -> {
  if (line = steps.shift)
    Reline.insert_text(line)
    Reline.redisplay
  end

  if steps.empty?
    Reline.pre_input_hook = nil
  end
}

binding.irb
