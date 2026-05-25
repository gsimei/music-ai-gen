# frozen_string_literal: true

# Immutable result object returned by all service objects.
# Use success? / failure? to branch, and value / errors to access data.
#
# Example:
#   result = MyService.call(param: "value")
#   if result.success?
#     render json: result.value
#   else
#     render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
#   end
class ServiceResult
  attr_reader :value, :errors

  def initialize(success:, value:, errors:)
    @success = success
    @value   = value
    @errors  = errors
    freeze
  end

  def success?
    @success
  end

  def failure?
    !@success
  end

  def ==(other)
    other.is_a?(ServiceResult) &&
      other.success? == success? &&
      other.value == value &&
      other.errors == errors
  end
  alias eql? ==

  def hash
    [ @success, @value, @errors ].hash
  end
end
