# frozen_string_literal: true

module Revisable
  class Log
    include Enumerable

    attr_reader :commits

    def initialize(commits)
      @commits = commits
    end

    def each(&block)
      @commits.each(&block)
    end

    def size
      @commits.size
    end
    alias_method :length, :size

    def first(n = nil)
      n ? self.class.new(@commits.first(n)) : @commits.first
    end

    def last(n = nil)
      n ? self.class.new(@commits.last(n)) : @commits.last
    end

    def empty?
      @commits.empty?
    end

    def to_text
      @commits.map do |commit|
        prefix = commit.merge? ? "M" : "*"
        "#{prefix} #{commit.sha[0..6]} #{commit.message}"
      end.join("\n")
    end
  end
end
