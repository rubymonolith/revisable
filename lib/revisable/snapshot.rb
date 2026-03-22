# frozen_string_literal: true

module Revisable
  class Snapshot
    attr_reader :commit, :fields

    def initialize(commit:, fields:)
      @commit = commit
      @fields = fields
      @field_set = commit.field_set
    end

    def [](field_name)
      @field_set.data_for(field_name)
    end

    def to_h
      fields.each_with_object({}) do |field, hash|
        hash[field.to_sym] = self[field]
      end
    end

    def respond_to_missing?(method, include_private = false)
      fields.map(&:to_sym).include?(method.to_sym) || super
    end

    def method_missing(method, *args)
      if fields.map(&:to_sym).include?(method.to_sym)
        self[method]
      else
        super
      end
    end
  end
end
