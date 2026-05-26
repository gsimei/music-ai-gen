ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Minitest 6 removed Object#stub. Re-add a compatible implementation so tests
# that use SomeClass.stub(:method, callable) { block } continue to work.
class Object
  def stub(method_name, val_or_callable)
    backed_up = :"__stub_backup_#{method_name}__"
    mc = class << self; self; end
    mc.alias_method(backed_up, method_name)
    mc.define_method(method_name) do |*args, **kwargs, &blk|
      if val_or_callable.respond_to?(:call)
        val_or_callable.call(*args, **kwargs, &blk)
      else
        val_or_callable
      end
    end
    yield
  ensure
    mc.undef_method(method_name)
    mc.alias_method(method_name, backed_up)
    mc.undef_method(backed_up)
  end
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include ActiveJob::TestHelper
  end
end

# Backport `kwargs:` support for assert_enqueued_with.
#
# Rails 8.1's assert_enqueued_with does not accept a `kwargs:` keyword.
# ActiveJob serializes keyword arguments as the last element of the args array
# (a Hash with a `_aj_ruby2_keywords` key that is stripped on deserialization).
# After deserialization, the kwargs hash has SYMBOL keys.
#
# WebMock's hash_including stringifies expected keys, so we must stringify the
# actual_kwargs before comparing with a hash_including matcher.
#
# This patch also makes `args:` matching tolerant of a trailing kwargs hash so
# that assert_enqueued_with(args: [positional]) matches jobs enqueued as
# perform_later(positional, keyword: value).
module ActiveJobKwargsHelper
  # Returns true if the last element of +args+ is a deserialized ActiveJob
  # kwargs hash (all symbol keys).
  def self.trailing_kwargs_hash?(args)
    args.is_a?(Array) &&
      args.last.is_a?(Hash) &&
      args.last.keys.all? { |k| k.is_a?(Symbol) }
  end

  def assert_enqueued_with(job: nil, args: nil, kwargs: nil, at: nil, queue: nil, priority: nil, &block)
    if kwargs || args
      kwargs_matcher  = kwargs
      positional_args = args

      args = lambda do |actual_args|
        # Split actual args into positional part and trailing kwargs hash (if any).
        if ActiveJobKwargsHelper.trailing_kwargs_hash?(actual_args)
          actual_positional = actual_args[0..-2]
          # Stringify keys so WebMock hash_including matchers (which stringify
          # expected keys internally) can match correctly.
          actual_kwargs = actual_args.last.transform_keys(&:to_s)
        else
          actual_positional = actual_args
          actual_kwargs     = {}
        end

        # Check positional args constraint when provided.
        if positional_args
          positional_match = if positional_args.respond_to?(:call)
            positional_args.call(actual_positional)
          else
            actual_positional == positional_args
          end
          return false unless positional_match
        end

        # Check kwargs constraint when provided.
        if kwargs_matcher
          kwarg_match = (kwargs_matcher === actual_kwargs)
          return false unless kwarg_match
        end

        true
      end
    end

    super(job: job, args: args, at: at, queue: queue, priority: priority, &block)
  end
end

ActiveSupport::TestCase.prepend(ActiveJobKwargsHelper)
ActionDispatch::IntegrationTest.prepend(ActiveJobKwargsHelper)

# Ensure ActionMailer uses test delivery in all test cases
ActionMailer::Base.delivery_method = :test
