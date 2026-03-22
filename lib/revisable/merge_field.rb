# frozen_string_literal: true

module Revisable
  class MergeField
    attr_reader :field_name, :status, :ancestor, :resolved_value, :versions

    def initialize(field_name:, status:, versions:, ancestor:, auto_resolved_value: nil)
      @field_name = field_name.to_sym
      @status = status
      @versions = versions
      @ancestor = ancestor
      @auto_resolved_value = auto_resolved_value
      @resolved_value = nil
    end

    def version(branch_name)
      @versions[branch_name.to_s]
    end

    def conflicted?
      status == :conflicted && !resolved?
    end

    def auto_resolved?
      status == :auto_resolved
    end

    def unchanged?
      status == :unchanged
    end

    def resolved?
      !@resolved_value.nil?
    end

    def resolve(value)
      @resolved_value = case value
      when :ancestor then ancestor
      when Symbol, String
        name = value.to_s
        if @versions.key?(name)
          @versions[name]
        else
          value.to_s
        end
      else
        value.to_s
      end
    end

    def value
      if resolved?
        resolved_value
      elsif auto_resolved? || unchanged?
        @auto_resolved_value
      end
    end
  end
end
