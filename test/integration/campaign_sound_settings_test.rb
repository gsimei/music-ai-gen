require "test_helper"

class CampaignSoundSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @order = orders(:b2b_pending)
    @order.update!(status: "lyrics_ready", music_regen_limit: 2, lyrics_regen_limit: 20)
    @campaign = Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro na terça",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @campaign.sync_briefing!
    @order.lyrics_drafts.create!(version: 1, source: "ai_generated", content: "Bella Napoli, pizza em dobro na terça!")
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  test "merchant chooses sound before checkout and sees it in the saved form" do
    post campaigns_path, params: { campaign: @campaign.attributes.slice("business_name", "offer", "contact", "call_to_action", "style").merge(
      musical_genre: "forro", vocal_gender: "female", music_notes: "Sanfona em destaque") }
    created = Campaign.last
    assert_redirected_to campaign_path(created)
    assert_equal "female", created.vocal_gender
    assert_equal "forro", created.musical_genre
    assert_includes created.order.briefing.music_style, "accordion"
    follow_redirect!
    assert_includes response.body, "Forró · Voz feminina · Animado"
    assert_select 'input[type="radio"][name="campaign[musical_genre]"][checked][value="forro"]'
    assert_select 'input[type="radio"][name="campaign[vocal_gender]"][checked][value="female"]'
    assert_select 'textarea[name="campaign[music_notes]"]', text: "Sanfona em destaque"
  end

  test "the studio lyrics phase shows the saved sound as checked tiles, not selects" do
    @campaign.update!(musical_genre: "forro", vocal_gender: "female", music_notes: "Sanfona em destaque")
    get order_chat_path(order_id: @order.id)
    assert_select '#creation-sound input[type="radio"][name="campaign[musical_genre]"][checked][value="forro"]'
    assert_select '#creation-sound input[type="radio"][name="campaign[vocal_gender]"][checked][value="female"]'
    assert_select '#creation-sound textarea[name="campaign[music_notes]"]', text: "Sanfona em destaque"
    assert_select "#creation-sound select", count: 0
  end

  test "invalid choices cannot create a paid campaign" do
    assert_no_difference [ "Campaign.count", "Order.count" ] do
      post campaigns_path, params: { campaign: @campaign.attributes.slice("business_name", "offer", "contact", "call_to_action", "style").merge(
        musical_genre: "unknown", vocal_gender: "invalid", music_notes: "x" * 241) }
    end
    assert_response :unprocessable_entity
  end

  test "saved direction controls the first paid API request and does not spend a round on save" do
    before = @order.creation_version
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count", "LyricsDraft.count" ] do
      patch order_chat_sound_settings_path(order_id: @order.id), params: { campaign: {
        musical_genre: "forro", vocal_gender: "female", style: "animado", music_notes: "Sanfona em destaque", model: "mureka-9.5" } }, headers: @headers
    end
    assert_response :success
    assert_not_equal before, @order.reload.creation_version
    assert_equal "female", @campaign.reload.vocal_gender
    @order.update!(status: "lyrics_approved")
    generation = Campaigns::MusicRounds.call(order: @order).value
    captured = nil
    stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL).with { |request| captured = JSON.parse(request.body); true }
      .to_return(status: 200, body: { id: "settings-first-round" }.to_json)
    GenerateCampaignMusicJob.perform_now(generation.id)
    assert_equal "female", captured["gender"]
    assert_equal "mureka-9", captured["model"]
    assert_equal 2, captured["n"]
    assert_includes captured["prompt"], "Brazilian forro"
    assert_includes captured["prompt"], "Sanfona em destaque"
    assert_includes captured["prompt"], "female singing voice"
    refute captured.key?("voice_id")
    assert_equal @campaign.sound_settings, generation.request_payload["sound_settings"]
    assert_equal 1, @order.generation_costs.where(operation: "music").count
  end

  test "changing voice and genre replaces old direction without rewriting old versions" do
    @campaign.update!(musical_genre: "forro", vocal_gender: "female")
    @campaign.sync_briefing!
    @order.update!(status: "lyrics_approved")
    first = Campaigns::MusicRounds.call(order: @order).value
    first.update!(status: "completed")
    original = first.request_payload.deep_dup
    asset = first.order_assets.create!(order: @order, kind: "music_variant", variant_index: 0)
    @order.update!(status: "preview_ready", favorite_music_asset: asset)
    patch order_chat_sound_settings_path(order_id: @order.id), params: { campaign: {
      musical_genre: "pagode", vocal_gender: "male", style: "acolhedor", music_notes: "Poucos instrumentos" } }, headers: @headers
    assert_response :success
    next_round = Campaigns::MusicRounds.call(order: @order.reload, asset_id: asset.id, feedback: "Refrão mais curto").value
    assert_equal "male", next_round.request_payload["gender"]
    assert_includes next_round.request_payload["prompt"], "Brazilian pagode"
    assert_includes next_round.request_payload["prompt"], "Poucos instrumentos"
    refute_includes next_round.request_payload["prompt"], "Brazilian forro"
    refute_includes next_round.request_payload["prompt"], "female singing voice"
    assert_equal original, first.reload.request_payload
    assert_equal asset.id, @order.reload.favorite_music_asset_id
    next_round.update!(status: "failed")
    @order.update!(status: "music_failed")
    patch order_chat_sound_settings_path(order_id: @order.id), params: { campaign: { vocal_gender: "auto" } }, headers: @headers
    assert_response :success
    retry_round = Campaigns::MusicRounds.call(order: @order.reload, retry_failed: true).value
    assert_nil retry_round.request_payload["gender"]
    assert_equal "auto", retry_round.request_payload["sound_settings"]["vocal_gender"]
    assert_equal "male", next_round.reload.request_payload["gender"]
  end

  test "settings are rejected while generating, after approval and for other customers" do
    original = @campaign.sound_settings
    %w[music_generating approved].each do |state|
      @order.update!(status: state)
      patch order_chat_sound_settings_path(order_id: @order.id), params: { campaign: { vocal_gender: "male" } }, headers: @headers
      assert_response :unprocessable_entity
      assert_equal original, @campaign.reload.sound_settings
    end
    sign_out :user
    sign_in users(:customer_other)
    patch order_chat_sound_settings_path(order_id: @order.id), params: { campaign: { vocal_gender: "male" } }, headers: @headers
    assert_response :not_found
  end
end
