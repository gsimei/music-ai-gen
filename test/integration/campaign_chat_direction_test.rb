require "test_helper"

class CampaignChatDirectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_pending)
    @order.update!(status: "lyrics_ready")
    @campaign = Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @campaign.sync_briefing!
    @order.lyrics_drafts.create!(version: 1, source: "ai_generated", content: "Bella Napoli, pizza em dobro!")
  end

  test "chat choices reach saved controls briefing and paid request without spending on save" do
    response = { reply: "Salvei pagode com voz masculina.", sound_settings: { musical_genre: "pagode", vocal_gender: "male", music_notes: "Cavaquinho em destaque" },
      briefing: { about: "Outro negócio", keywords: "Outra oferta", instrumental: true }, generate_music: false }
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
      answer(response) { ConversationalReplyJob.perform_now(@order.id, "Quero pagode com voz masculina e cavaquinho. Só salve.") }
    end
    assert_equal "pagode", @campaign.reload.musical_genre
    assert_equal "male", @campaign.vocal_gender
    assert_equal "Pizza em dobro", @campaign.offer
    assert_includes @order.briefing.reload.music_style, "pagode"
    refute @order.briefing.extra_params["instrumental"]
    get order_chat_path(order_id: @order.id)
    assert_select 'select[name="campaign[musical_genre]"] option[selected][value="pagode"]'
    assert_select 'select[name="campaign[vocal_gender]"] option[selected][value="male"]'
    answer(reply: "Vamos gerar.", sound_settings: {}, generate_music: true) { ConversationalReplyJob.perform_now(@order.id, "Pode gerar") }
    GenerateMusicJob.perform_now(@order.id)
    generation = @order.music_generations.last
    assert_equal "male", generation.request_payload["gender"]
    assert_includes generation.request_payload["prompt"], "Cavaquinho em destaque"
    assert_includes generation.request_payload["prompt"], "pagode"
  end

  test "a delayed response cannot overwrite newer controls or generate music" do
    delayed = ->(**_) do
      Campaigns::SoundSettings.call(order: Order.find(@order.id), settings: { "vocal_gender" => "female" })
      { content: { reply: "Vou gerar", sound_settings: { vocal_gender: "male" }, generate_music: true }.to_json }
    end
    assert_no_difference "MusicGeneration.count" do
      LyricsGenerator::ClaudeClient.stub(:chat, delayed) { ConversationalReplyJob.perform_now(@order.id, "Voz masculina") }
    end
    assert_equal "female", @campaign.reload.vocal_gender
    assert_includes @order.briefing_messages.last.content, "Não iniciei"
  end

  test "invalid preferences and string flags never trigger a paid generation" do
    answer(reply: "Gerando", sound_settings: { vocal_gender: "invalid" }, generate_music: true) do
      assert_no_difference("MusicGeneration.count") { ConversationalReplyJob.perform_now(@order.id, "Mudar voz") }
    end
    assert_equal "auto", @campaign.reload.vocal_gender
    answer(reply: "Escolhas salvas", sound_settings: {}, generate_music: "false", ready: "true") do
      assert_no_difference([ "MusicGeneration.count", "LyricsDraft.count" ]) { ConversationalReplyJob.perform_now(@order.id, "Só conferir") }
    end
  end

  test "confirmation preserves manual settings changed since earlier messages" do
    @campaign.update!(musical_genre: "forro", vocal_gender: "female")
    @campaign.sync_briefing!
    answer(reply: "Vamos gerar", sound_settings: {}, generate_music: true,
      briefing: { music_style: "pop", gender: "male" }) { ConversationalReplyJob.perform_now(@order.id, "Sim") }
    GenerateMusicJob.perform_now(@order.id)
    payload = @order.music_generations.last.request_payload
    assert_equal "female", payload["gender"]
    assert_includes payload["prompt"], "Brazilian forro"
  end

  private

  def answer(response)
    LyricsGenerator::ClaudeClient.stub(:chat, { content: response.to_json }) { yield }
  end
end
