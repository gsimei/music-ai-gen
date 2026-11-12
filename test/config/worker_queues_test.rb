require "test_helper"
require "yaml"
require "erb"

class WorkerQueuesTest < ActiveSupport::TestCase
  test "every application job and mail delivery has a production worker" do
    Rails.application.eager_load!
    config = YAML.safe_load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
    queues = config.fetch("production").fetch("workers").flat_map { |worker| Array(worker.fetch("queues")) }
    jobs = Dir[Rails.root.join("app/jobs/*.rb")].map { |path| File.basename(path, ".rb").camelize.constantize }
    jobs.each do |job|
      assert_includes queues, job.new.queue_name, "No worker serves #{job.name}"
    end
    assert_includes queues, (ActionMailer::Base.deliver_later_queue_name || ActiveJob::Base.default_queue_name).to_s
  end
end
