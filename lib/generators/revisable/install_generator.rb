# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module Revisable
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_migration_file
      migration_template "create_revisable_tables.rb.erb", "db/migrate/create_revisable_tables.rb"
    end
  end
end
