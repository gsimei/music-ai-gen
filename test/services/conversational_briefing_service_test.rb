require "test_helper"

class ConversationalBriefingServiceTest < ActiveSupport::TestCase
  test "vocal false is persisted instead of being treated as blank" do
    order = orders(:b2b_paid)
    order.briefing.update!(extra_params: { "instrumental" => true })
    response = { content: { reply: "Vamos escrever a letra.", ready: true, generate_music: false, briefing: { instrumental: false } }.to_json }
    LyricsGenerator::ClaudeClient.stub(:chat, ->(**_) { response }) do
      result = ConversationalBriefingService.call(order: order, new_message: "Quero cantada, não instrumental")
      assert result.success?
      assert_equal false, order.briefing.reload.extra_params["instrumental"]
      assert_equal true, result.value[:ready]
    end
  end
end
