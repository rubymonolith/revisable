# frozen_string_literal: true

module Revisable
  class Branch
    attr_reader :ref

    def initialize(ref)
      @ref = ref
    end

    def name
      ref.name
    end

    def commit
      ref.commit
    end

    def commit_sha
      ref.commit_sha
    end

    def tip(fields:)
      Snapshot.new(commit: commit, fields: fields)
    end

    def to_s
      name
    end

    def ==(other)
      other.is_a?(Branch) && name == other.name && commit_sha == other.commit_sha
    end
  end
end
