require "test_helper"

class GenerationCostTest < ActiveSupport::TestCase
  test "event snapshots exchange rate and does not invent unknown costs" do
    cost = GenerationCost.record!(order: orders(:b2b_paid), operation: "music", provider: "mureka", model: "mureka-9", usd: BigDecimal("0.09"), usage: { requested_songs: 2 })
    assert_equal BigDecimal("0.09") * cost.usd_brl, cost.estimated_brl
    assert_equal "estimated", cost.status
    unknown = GenerationCost.record!(order: orders(:b2b_paid), operation: "video_render", provider: "local", model: "ffmpeg", usage: { wall_seconds: 3.2 })
    assert_nil unknown.estimated_brl
    assert_equal "unpriced", unknown.status
    assert_equal 3.2, unknown.usage["wall_seconds"]
  end

  test "chat records actual tokens on every attempt including empty responses" do
    order = orders(:b2b_paid)
    Campaign.create!(order: order, business_name: "Teste", offer: "Pizza em dobro", contact: "@teste", call_to_action: "Peça", style: "animado")
    responses = [
      { "id" => "response1", "choices" => [ { "message" => { "content" => "" } } ], "usage" => { "prompt_tokens" => 1000, "completion_tokens" => 100, "prompt_tokens_details" => { "cached_tokens" => 200 } } },
      { "id" => "response2", "choices" => [ { "message" => { "content" => '{"reply":"oi"}' } } ], "usage" => { "prompt_tokens" => 1000, "completion_tokens" => 100 } }
    ]
    client = Object.new
    client.define_singleton_method(:chat) { |**| responses.shift }
    original_key = ENV["OPENAI_API_KEY"]
    ENV["OPENAI_API_KEY"] = "test-key"
    OpenAI::Client.stub(:new, client) do
      LyricsGenerator::ClaudeClient.chat(order: order, system: "test", messages: [])
    end
    costs = order.generation_costs.order(:id)
    assert_equal 2, costs.count
    assert_equal BigDecimal("0.000195"), costs.first.estimated_usd
    assert_equal BigDecimal("0.00021"), costs.last.estimated_usd
    assert_equal [ "response1", "response2" ], costs.pluck(:provider_request_id)
  ensure
    ENV["OPENAI_API_KEY"] = original_key
  end
end
