# frozen_string_literal: true

require_relative "lib/revisable/version"

Gem::Specification.new do |spec|
  spec.name = "revisable"
  spec.version = Revisable::VERSION
  spec.authors = ["Brad Gessler"]
  spec.email = ["bradgessler@gmail.com"]

  spec.summary = "Git-like versioning for ActiveRecord text content"
  spec.description = "Content-addressed versioning with branches, merges, diffs, and tags for ActiveRecord models. Like git, but in your database."
  spec.homepage = "https://github.com/rubymonolith/revisable"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0"
  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "diff-lcs", "~> 1.5"
end
