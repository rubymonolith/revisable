# frozen_string_literal: true

require "active_record"
require "active_support"
require "diff/lcs"

require_relative "revisable/version"

# Core (no AR dependency in these objects)
require_relative "revisable/field_set"
require_relative "revisable/snapshot"
require_relative "revisable/renderers/text_renderer"
require_relative "revisable/renderers/html_renderer"
require_relative "revisable/field_diff"
require_relative "revisable/diff"
require_relative "revisable/log"
require_relative "revisable/merge_field"
require_relative "revisable/merge"

# ActiveRecord models
require_relative "revisable/blob"
require_relative "revisable/commit"
require_relative "revisable/commit_field"
require_relative "revisable/ref"
require_relative "revisable/branch"
require_relative "revisable/tag"

# ActiveRecord integration
require_relative "revisable/repository"
require_relative "revisable/model"

module Revisable
  class Error < StandardError; end
  class ConflictError < Error; end
  class RefNotFoundError < Error; end
  class UnresolvedConflictsError < Error; end
  class StaleRefError < Error; end
end
