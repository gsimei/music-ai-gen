require "test_helper"
require "timeout"

class LyricsGeneratorConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "two stale concurrent regenerations with one remaining allowance make one provider call" do
    order = orders(:b2b_lyrics_ready)
    order.update!(lyrics_regen_used: order.lyrics_regen_limit - 1)
    parent_id = order.current_draft.id
    ready = Queue.new
    start = Queue.new
    calls = Queue.new
    threads = []

    LyricsGenerator::MurekaLyricsClient.stub(:call, ->(**) {
      calls << true
      ServiceResult.new(success: true, value: { lyrics: "Nova letra", title: "Teste", latency_ms: 1 }, errors: nil)
    }) do
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            stale_order = Order.find(order.id)
            ready << true
            start.pop
            LyricsGenerator::Generator.call(order: stale_order, mode: :regen, parent_draft_id: parent_id)
          end
        end
      end
      Timeout.timeout(10) { 2.times { ready.pop } }
      2.times { start << true }
      results = Timeout.timeout(15) { threads.map(&:value) }
      assert_equal 1, results.count(&:success?)
      assert_equal [ :regen_limit_reached ], results.select(&:failure?).map(&:errors)
    end
    assert_equal 1, calls.size
    assert_equal order.lyrics_regen_limit, order.reload.lyrics_regen_used
    assert_equal 2, order.lyrics_drafts.count
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
  end
end
