# frozen_string_literal: true

# Base class for all service objects.
# Subclasses declare attributes with ActiveModel::Attributes, add validations,
# and implement #call returning success_result or failure_result.
#
# Usage:
#   class MyService < BaseService
#     attribute :param, :string
#     validates :param, presence: true
#
#     def call
#       return failure_result(errors) unless valid?
#       # business logic here
#       success_result(computed_value)
#     end
#   end
#
#   result = MyService.call(param: "value")
#   result.success? # => true
class BaseService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Class-level entry point — instantiates and calls in one step.
  def self.call(...)
    new(...).call
  end

  private

  # Returns a successful ServiceResult wrapping an optional value.
  def success_result(value = nil)
    ServiceResult.new(success: true, value: value, errors: nil)
  end

  # Returns a failed ServiceResult. Pass an ActiveModel::Errors object,
  # an array of strings, or any object that describes the failure.
  def failure_result(errors)
    ServiceResult.new(success: false, value: nil, errors: errors)
  end
end
