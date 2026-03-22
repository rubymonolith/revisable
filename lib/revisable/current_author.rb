# frozen_string_literal: true

module Revisable
  module CurrentAuthor
    def self.set(author)
      Thread.current[:revisable_current_author] = author
    end

    def self.get
      Thread.current[:revisable_current_author]
    end

    def self.clear
      Thread.current[:revisable_current_author] = nil
    end

    def self.with(author)
      previous = get
      set(author)
      yield
    ensure
      set(previous)
    end
  end
end
