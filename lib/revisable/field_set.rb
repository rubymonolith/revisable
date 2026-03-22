# frozen_string_literal: true

module Revisable
  class FieldSet
    include Enumerable

    def initialize(fields = {})
      @fields = fields.transform_keys(&:to_sym)
    end

    def [](field_name)
      @fields[field_name.to_sym]
    end

    def each(&block)
      @fields.each(&block)
    end

    def keys
      @fields.keys
    end

    def values
      @fields.values
    end

    def sha_for(field_name)
      self[field_name]&.sha
    end

    def data_for(field_name)
      self[field_name]&.data
    end

    def shas
      @fields.transform_values(&:sha)
    end

    def diff(other)
      keys.each_with_object({}) do |field, result|
        result[field] = sha_for(field) != other.sha_for(field)
      end
    end

    def empty?
      @fields.empty?
    end

    def self.empty
      new({})
    end
  end
end
