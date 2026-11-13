require "test_helper"

class CampaignGuidedStudioTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12",
      contact: "@cafe", call_to_action: "Peça agora", style: "animado")
    @campaign.sync_briefing!
    @draft = @order.current_draft
    @asset = order_assets(:music_variant_a)
    @asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4", metadata: { duration_seconds: 30 })
    @asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: @asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
    @asset.update!(campaign_preview_status: "ready")
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
    clear_enqueued_jobs
  end

  test "music workspace leads with listening and keeps one optional editor" do
    get order_chat_path(order_id: @order.id)
    assert_response :success
    assert_select ".ui-version", count: 2
    assert_select ".ui-btn-primary", text: /Usar a Versão A e montar o vídeo/, count: 1
    assert_select "input[type=radio][name=asset_id]", count: 1
    assert_select "#music-changes:not([open])", count: 1
    assert_select "#editable-lyrics", count: 1
    assert_select ".creative-video-photos, .creative-video-appearance, .excerpt-editor, .creative-favorite-label, .jp-assistant", count: 0
    assert_select ".creative-progress", text: /ajustes disponíveis|rodadas prontas/, count: 0
  end

  test "selection opens video setup without approving charging or rendering and can be undone" do
    assert_no_enqueued_jobs only: RenderCampaignVideoJob do
      post order_chat_select_music_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    end
    assert_response :success
    assert_equal @asset.id, @campaign.reload.selected_music_asset_id
    assert @order.reload.preview_ready?
    assert_equal "pending", @campaign.video_status
    assert_nil @order.approved_music_generation_id
    get order_chat_path(order_id: @order.id)
    assert_select ".creative-video-setup", count: 1
    assert_select ".creative-video-photos, .creative-video-appearance", count: 2
    assert_select "button", text: "Gerar meu vídeo"
    assert_select "#editable-lyrics", count: 0

    post order_chat_change_music_path(order_id: @order.id), headers: @headers
    assert_response :success
    assert_nil @campaign.reload.selected_music_asset_id
    assert_equal 1, @order.completed_music_rounds
    get order_chat_path(order_id: @order.id)
    assert_select "#music-changes", count: 1
  end

  test "one submission saves lyrics and sound before generating and preserves old audio lyrics" do
    original = @draft.content
    assert_difference "LyricsDraft.count", 1 do
      assert_difference "MusicGeneration.count", 1 do
        post order_chat_creation_path(order_id: @order.id), params: creation_params.merge(intent: "generate"), headers: @headers
      end
    end
    assert_response :success
    generation = @order.music_generations.order(:iteration).last
    assert_equal "Café fresquinho por doze reais!", generation.request_payload["lyrics"]
    assert_equal "forro", generation.request_payload.dig("sound_settings", "musical_genre")
    assert_equal original, @asset.music_generation.lyrics_draft.reload.content
    assert_equal 0, @order.reload.lyrics_regen_used
    assert_equal 1, @order.completed_music_rounds
    assert_no_difference [ "LyricsDraft.count", "MusicGeneration.count" ] do
      post order_chat_creation_path(order_id: @order.id), params: creation_params.merge(intent: "generate"), headers: @headers
    end
    assert_response :unprocessable_entity
  end

  test "saving and rewriting edited lyrics do not start music" do
    assert_no_difference "MusicGeneration.count" do
      post order_chat_creation_path(order_id: @order.id), params: creation_params.merge(intent: "save"), headers: @headers
    end
    assert_response :success
    edited = @order.current_draft
    assert_equal "Café fresquinho por doze reais!", edited.content
    assert_enqueued_with(job: RewriteCampaignLyricsJob, args: ->(args) { args[0] == @order.id && args[1].is_a?(String) && args[2..] == [ edited.id, "Mais curto" ] }) do
      post order_chat_creation_path(order_id: @order.id), params: creation_params.merge(draft_id: edited.id, intent: "rewrite", lyrics_feedback: "Mais curto"), headers: @headers
    end
    assert_response :success
    assert @order.reload.preview_ready?
  end

  test "invalid or stale combined changes never partially save" do
    original = @draft.content
    [ creation_params.merge(draft_id: -1), creation_params.deep_merge(campaign: { musical_genre: "invalid" }), creation_params.merge(feedback: "a" * 401) ].each do |attributes|
      assert_no_difference [ "LyricsDraft.count", "MusicGeneration.count" ] do
        post order_chat_creation_path(order_id: @order.id), params: attributes.merge(intent: "generate"), headers: @headers
      end
      assert_response :unprocessable_entity
      assert_equal original, @order.current_draft.content
      assert_equal "auto", @campaign.reload.musical_genre
    end
  end

  test "first generation uses the visible edited text and settings in one submission" do
    @order.music_generations.destroy_all
    @order.update!(status: "lyrics_ready")
    @draft.update!(is_approved: false, is_locked: false)
    assert_enqueued_with(job: GenerateMusicJob, args: [ @order.id ]) do
      post order_chat_creation_path(order_id: @order.id), params: creation_params.merge(intent: "generate"), headers: @headers
    end
    assert_response :success
    assert @order.reload.lyrics_approved?
    assert_equal "Café fresquinho por doze reais!", @order.approved_lyrics_draft.content
    assert_equal "forro", @campaign.reload.musical_genre
  end

  test "all three generations keep selection available and close the editing path" do
    [ 2, 3 ].each do |iteration|
      @order.music_generations.create!(iteration: iteration, provider: "mureka", status: "completed", lyrics_draft: @draft, music_style: "pop")
    end
    get order_chat_path(order_id: @order.id)
    assert_select "#editable-lyrics", count: 0
    assert_select "details#music-round-1 input[type=radio][name=asset_id][form=music-pick][value=?]", @asset.id.to_s
    assert_select ".ui-btn-primary", text: /Usar a Versão A da rodada 1/
    assert_no_difference [ "LyricsDraft.count", "MusicGeneration.count" ] do
      post order_chat_creation_path(order_id: @order.id), params: creation_params.merge(intent: "generate"), headers: @headers
    end
    assert_response :unprocessable_entity
    post order_chat_select_music_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    assert_response :success
    assert_equal @asset.id, @campaign.reload.selected_music_asset_id
  end

  test "selection is scoped to the owner and completed prepared music" do
    post order_chat_select_music_path(order_id: @order.id), params: { asset_id: order_assets(:final_mp3).id }, headers: @headers
    assert_response :unprocessable_entity
    post order_chat_select_music_path(order_id: @order.id), params: { asset_id: order_assets(:music_variant_b).id }, headers: @headers
    assert_response :unprocessable_entity
    assert_nil @campaign.reload.selected_music_asset_id
    sign_out :user
    sign_in users(:customer_other)
    post order_chat_select_music_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    assert_response :not_found
  end

  test "final video uses the selected old version and its original lyrics" do
    Campaigns::LyricsEditor.call(order: @order, draft_id: @draft.id, content: "Uma letra diferente")
    post order_chat_select_music_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    assert_enqueued_with(job: RenderCampaignVideoJob, args: [ @campaign.id ]) do
      post order_chat_approve_music_path(order_id: @order.id), params: { asset_id: @asset.id, preview_revision: 0, video_revision: @campaign.reload.video_revision }, headers: @headers
    end
    assert_redirected_to campaign_path(@campaign)
    assert @order.reload.approved?
    assert_equal @draft.id, @order.approved_lyrics_draft_id
    post order_chat_change_music_path(order_id: @order.id), headers: @headers
    assert_response :unprocessable_entity
  end

  test "a video form from before changing the selection cannot finalize the campaign" do
    post order_chat_select_music_path(order_id: @order.id), params: { asset_id: @asset.id }, headers: @headers
    revision = @campaign.reload.video_revision
    post order_chat_change_music_path(order_id: @order.id), headers: @headers
    assert_no_enqueued_jobs only: RenderCampaignVideoJob do
      post order_chat_approve_music_path(order_id: @order.id), params: { asset_id: @asset.id, preview_revision: 0, video_revision: revision }, headers: @headers
    end
    assert_response :unprocessable_entity
    assert @order.reload.preview_ready?
  end

  private

  def creation_params
    { draft_id: @draft.id, content: "Café fresquinho por doze reais!", feedback: "Mais alegre",
      campaign: { musical_genre: "forro", vocal_gender: "female", style: "animado", music_notes: "" } }
  end
end
