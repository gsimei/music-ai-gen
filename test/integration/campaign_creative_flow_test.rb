require "test_helper"

class CampaignCreativeFlowTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_pending)
    @order.update!(status: "lyrics_ready", music_regen_limit: 2, lyrics_regen_limit: 20)
    @campaign = Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro na terça",
      contact: "@bellanapoli", call_to_action: "Peça agora", style: "animado")
    @campaign.sync_briefing!
    @draft = @order.lyrics_drafts.create!(version: 1, source: "ai_generated", content: "Bella Napoli, pizza em dobro na terça!")
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
    clear_enqueued_jobs
  end

  test "merchant edits lyrics, compares three pairs and approves the favorite from the first round" do
    patch order_chat_edit_lyrics_path(order_id: @order.id), params: { draft_id: @draft.id, content: "Bella Napoli, duas pizzas na terça!" }, headers: @headers
    assert_response :success
    assert_equal "Bella Napoli, pizza em dobro na terça!", @draft.reload.content
    assert_equal "user_edited", @order.current_draft.source
    assert_equal 2, @order.lyrics_drafts.count
    assert_equal 0, @order.reload.lyrics_regen_used

    post order_chat_approve_lyrics_path(order_id: @order.id), params: { draft_id: @order.current_draft.id }, headers: @headers
    GenerateMusicJob.perform_now(@order.id)
    first = finish_latest_round
    favorite = first.order_assets.first
    post order_chat_favorite_music_path(order_id: @order.id), params: { asset_id: favorite.id }, headers: @headers
    assert_response :success
    assert_equal favorite.id, @order.reload.favorite_music_asset_id

    2.times do |index|
      post order_chat_regenerate_music_path(order_id: @order.id), params: { asset_id: favorite.id, feedback: "Mais ritmo e voz feminina #{index}" }, headers: @headers
      assert_response :success
      assert_equal favorite.id, @order.reload.favorite_music_asset_id
      generation = @order.music_generations.order(:iteration).last
      assert_equal first.id, generation.parent_generation_id
      assert_equal favorite.id, generation.request_payload["source_asset_id"]
      assert_includes generation.request_payload["prompt"], "Mais ritmo e voz feminina #{index}"
      finish_latest_round
    end
    assert_equal 6, @order.all_music_assets.count
    assert_equal 3, @order.completed_music_rounds
    assert_equal 0, @order.music_regen_remaining
    get order_chat_path(order_id: @order.id)
    assert_select ".creative-version", count: 6
    assert_select ".creative-favorite-label", text: /Sua favorita/
    assert_select 'audio source[type="audio/mp4"]', count: 6
    assert_select 'audio source[type="audio/mpeg"]', count: 6
    assert_select 'form[action=?]', order_chat_regenerate_music_path(order_id: @order.id), count: 0
    assert_no_difference "MusicGeneration.count" do
      post order_chat_regenerate_music_path(order_id: @order.id), params: { feedback: "Mais uma" }, headers: @headers
    end
    assert_response :unprocessable_entity
    post order_chat_approve_music_path(order_id: @order.id), params: { asset_id: favorite.id }, headers: @headers
    assert_redirected_to campaign_path(@campaign)
    assert_equal first.id, @order.reload.approved_music_generation_id
    assert_equal first.lyrics_draft_id, @order.approved_lyrics_draft_id
    assert_equal "queued", @campaign.reload.video_status
    assert_equal 3, @order.generation_costs.where(operation: "music").count
    assert_equal BigDecimal("1.62"), @order.generation_costs.sum(:estimated_brl)
  end

  test "failure does not consume a round and retry preserves the exact request" do
    @order.update!(status: "lyrics_approved")
    Campaigns::MusicRounds.call(order: @order)
    first = finish_latest_round
    source = first.order_assets.last
    Campaigns::MusicRounds.call(order: @order.reload, feedback: "Voz feminina, mais forró", asset_id: source.id)
    failed = @order.music_generations.order(:iteration).last
    submit_round(failed)
    response = ServiceResult.new(success: true, errors: nil, value: { status: "failed" })
    MusicGenerator::MurekaStatusClient.stub(:call, response) { PollCampaignMusicJob.perform_now(failed.id) }
    assert_equal "music_failed", @order.reload.status
    assert_equal 1, @order.completed_music_rounds
    assert_equal 2, @order.music_regen_remaining
    assert_equal "uncertain", GenerationCost.find_by!(music_generation: failed).status
    post retry_generation_campaign_path(@campaign)
    retry_round = @order.music_generations.order(:iteration).last
    assert_equal failed.request_payload, retry_round.request_payload
    assert_equal failed.melody_hint, retry_round.melody_hint
    finish_latest_round
    assert_equal 2, @order.completed_music_rounds
    assert_equal 4, @order.all_music_assets.count
    assert_equal 3, @order.generation_costs.where(operation: "music").count
  end

  test "duplicate submissions and polls cannot generate or charge twice" do
    @order.update!(status: "lyrics_approved")
    result = Campaigns::MusicRounds.call(order: @order)
    generation = result.value
    assert_no_difference "MusicGeneration.count" do
      assert Campaigns::MusicRounds.call(order: @order.reload).failure?
    end
    submit_round(generation)
    assert_no_difference "GenerationCost.count" do
      GenerateCampaignMusicJob.perform_now(generation.id)
    end
    finish_latest_round(submit: false)
    assert_no_difference ["OrderAsset.count", "GenerationCost.count"] do
      PollCampaignMusicJob.perform_now(generation.id)
    end
  end

  test "retry honors lyrics explicitly edited after a failure without changing the failed snapshot" do
    @order.update!(status: "lyrics_approved")
    failed = Campaigns::MusicRounds.call(order: @order).value
    original = failed.request_payload.deep_dup
    failed.update!(status: "failed")
    @order.update!(status: "music_failed")
    edited = Campaigns::LyricsEditor.call(order: @order, draft_id: @draft.id, content: "Bella Napoli, pizza em dobro às terças. Peça já!").value
    retried = Campaigns::MusicRounds.call(order: @order, retry_failed: true).value
    assert_equal edited.id, retried.lyrics_draft_id
    assert_equal edited.content, retried.request_payload["lyrics"]
    assert_equal original["prompt"], retried.request_payload["prompt"]
    assert_equal original, failed.reload.request_payload
  end

  test "rewrites send the current edited text and instruction and keep earlier drafts" do
    post order_chat_regenerate_lyrics_path(order_id: @order.id), params: { feedback: "Inclua o slogan: tradição da família" }, headers: @headers
    assert_response :success
    token = @order.reload.lyrics_revision_token
    assert token.present?
    assert_no_enqueued_jobs only: RewriteCampaignLyricsJob do
      post order_chat_regenerate_lyrics_path(order_id: @order.id), params: { feedback: "Outro pedido duplicado" }, headers: @headers
    end
    assert_response :unprocessable_entity
    captured = nil
    stub_request(:post, LyricsGenerator::MurekaLyricsClient::MUREKA_LYRICS_URL)
      .with { |request| captured = JSON.parse(request.body); true }
      .to_return(status: 200, body: { title: "Bella Napoli", lyrics: "Bella Napoli, tradição da família! Pizza em dobro na terça." }.to_json)
    RewriteCampaignLyricsJob.perform_now(@order.id, token, @draft.id, "Inclua o slogan: tradição da família")
    assert_includes captured["prompt"], @draft.content
    assert_includes captured["prompt"], "Inclua o slogan: tradição da família"
    assert_equal 2, @order.lyrics_drafts.count
    assert_equal @draft.id, @order.current_draft.parent_draft_id
    assert_equal 1, @order.reload.lyrics_regen_used
    assert_nil @order.lyrics_revision_token
    assert_equal BigDecimal("0.054"), @order.generation_costs.sum(:estimated_brl)
    assert_no_difference ["GenerationCost.count", "LyricsDraft.count"] do
      RewriteCampaignLyricsJob.perform_now(@order.id, token, @draft.id, "duplicate")
    end
  end

  test "foreign assets, unpaid orders and stale lyric submissions are rejected" do
    foreign = order_assets(:music_variant_a)
    @order.update!(status: "preview_ready")
    post order_chat_favorite_music_path(order_id: @order.id), params: { asset_id: foreign.id }, headers: @headers
    assert_response :not_found
    sign_in users(:customer_b2b)
    result = Orders::MusicApprover.call(order: @order, asset_id: foreign.id)
    assert result.failure?
    assert_nil @order.reload.approved_music_generation_id
    assert Campaigns::MusicRounds.call(order: @order, asset_id: foreign.id).failure?
    assert_no_difference "LyricsDraft.count" do
      patch order_chat_edit_lyrics_path(order_id: @order.id), params: { draft_id: -1, content: "Stale" }, headers: @headers
    end
    assert_response :unprocessable_entity
    @order.update!(status: "pending")
    patch order_chat_edit_lyrics_path(order_id: @order.id), params: { draft_id: @draft.id, content: "Unpaid" }, headers: @headers
    assert_redirected_to campaign_path(@campaign)
    sign_out :user
    sign_in users(:customer_other)
    get order_chat_path(order_id: @order.id)
    assert_response :not_found
  end

  test "failed or incomplete pair keeps older choices available to approve" do
    @order.update!(status: "lyrics_approved")
    Campaigns::MusicRounds.call(order: @order)
    first = finish_latest_round
    Campaigns::MusicRounds.call(order: @order.reload, feedback: "Mais lento")
    generation = @order.music_generations.order(:iteration).last
    submit_round(generation)
    incomplete = ServiceResult.new(success: true, errors: nil, value: { status: "succeeded", choices: [{ url: "https://cdn.mureka.ai/one.mp3" }] })
    MusicGenerator::MurekaStatusClient.stub(:call, incomplete) { PollCampaignMusicJob.perform_now(generation.id) }
    assert_equal "failed", generation.reload.status
    assert_equal 2, @order.all_music_assets.count
    assert_equal 1, @order.completed_music_rounds
    assert Orders::MusicApprover.call(order: @order.reload, asset_id: first.order_assets.first.id).success?
  end

  test "saved audio can be played after provider URL expires" do
    @order.update!(status: "lyrics_approved")
    Campaigns::MusicRounds.call(order: @order)
    generation = finish_latest_round
    asset = generation.order_assets.first
    Campaigns::AudioDownload.stub(:call, ->(_url, destination) { File.binwrite(destination, "fake MP3") }) do
      ArchiveCampaignAudioJob.perform_now(asset.id)
    end
    assert asset.reload.audio.attached?
    assert_equal "fake MP3", asset.audio.download
    assert_includes asset.playback_url, "/rails/active_storage/"
    assert_no_difference "ActiveStorage::Blob.count" do
      ArchiveCampaignAudioJob.perform_now(asset.id)
    end
  end

  test "approval requires a prepared excerpt and preparation is scoped and idempotent" do
    @order.update!(status: "lyrics_approved")
    Campaigns::MusicRounds.call(order: @order)
    asset = finish_latest_round.order_assets.first
    asset.campaign_audio.purge
    asset.update!(campaign_preview_status: "pending")
    post order_chat_approve_music_path(order_id: @order.id), params: { asset_id: asset.id }, headers: @headers
    assert_response :unprocessable_entity
    assert_includes response.body, "Aguarde o trecho"
    assert_equal "preview_ready", @order.reload.status
    assert_enqueued_with(job: ArchiveCampaignAudioJob, args: [asset.id]) do
      post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: asset.id }, headers: @headers
    end
    assert_response :success
    assert_equal "queued", asset.reload.campaign_preview_status
    assert_no_enqueued_jobs only: ArchiveCampaignAudioJob do
      post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: asset.id }, headers: @headers
    end
    asset.update!(campaign_preview_status: "failed")
    assert_enqueued_with(job: ArchiveCampaignAudioJob, args: [asset.id]) do
      post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: asset.id }, headers: @headers
    end
    post order_chat_prepare_audio_path(order_id: @order.id), params: { asset_id: order_assets(:music_variant_a).id }, headers: @headers
    assert_response :not_found
    assert_equal 1, @order.completed_music_rounds
  end

  test "campaign model is fixed even when retrying an older model" do
    @order.update!(status: "lyrics_approved")
    failed = Campaigns::MusicRounds.call(order: @order).value
    failed.update!(status: "failed", model: "auto", request_payload: failed.request_payload.merge("model" => "auto", "duration" => 180))
    @order.update!(status: "music_failed")
    retried = Campaigns::MusicRounds.call(order: @order, retry_failed: true).value
    assert_equal "mureka-9", retried.model
    assert_equal "mureka-9", retried.request_payload["model"]
    assert_equal 2, retried.request_payload["n"]
    refute retried.request_payload.key?("duration")
    assert_equal "auto", failed.reload.model
  end

  private

  def submit_round(generation)
    stub_request(:post, MusicGenerator::MurekaClient::MUREKA_SONG_URL)
      .with { |request| body = JSON.parse(request.body); body["n"] == 2 && body["model"] == "mureka-9" && body["lyrics"].present? }
      .to_return(status: 200, body: { id: "test-round-#{generation.id}" }.to_json)
    GenerateCampaignMusicJob.perform_now(generation.id)
  end

  def finish_latest_round(submit: true)
    generation = @order.music_generations.order(:iteration).last
    submit_round(generation) if submit
    choices = 2.times.map { |i| { url: "https://cdn.mureka.ai/round-#{generation.id}-#{i}.mp3", duration_ms: 30_000, lyrics_sections: [] } }
    result = ServiceResult.new(success: true, errors: nil, value: { status: "succeeded", choices: choices })
    MusicGenerator::MurekaStatusClient.stub(:call, result) { PollCampaignMusicJob.perform_now(generation.id) }
    # Controller flow fixture. Real FFmpeg/packet equivalence is tested by AudioPreviewTest.
    generation.order_assets.each do |asset|
      asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4",
        metadata: { duration_seconds: 30 })
      asset.update!(campaign_preview_status: "ready")
    end
    @order.reload
    generation.reload
  end
end
