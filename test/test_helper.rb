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

# Ensure ActionMailer uses test delivery in all test cases
ActionMailer::Base.delivery_method = :test
