require "test_helper"

class CampaignAudioAccessTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @asset.audio.attach(io: StringIO.new("private original"), filename: "original.mp3", content_type: "audio/mpeg")
    @asset.campaign_audio.attach(io: StringIO.new("private excerpt"), filename: "excerpt.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: 0, duration_seconds: 30, source_blob_id: @asset.audio.blob.id, preview_version: 1 })
    @asset.update!(campaign_preview_status: "ready")
  end

  test "stock storage routes reject even known signed original and excerpt links" do
    [ @asset.audio.blob, @asset.campaign_audio.blob ].each do |blob|
      [ rails_storage_redirect_path(blob), rails_storage_proxy_path(blob) ].each do |path|
        get path
        assert_response :not_found
      end
      ActiveStorage::Current.set(url_options: { host: "b2b.lvh.me" }) do
        get URI(blob.url).request_uri
        assert_response :not_found
        [ "signed_id", "signed_blob_id" ].each do |query|
          get URI(blob.url).request_uri, params: { query => "invalid" }
          assert_response :not_found
          head URI(blob.url).request_uri, params: { query => "invalid" }
          assert_response :not_found
        end
      end
    end
  end

  test "legacy pages never expose provider recordings for campaigns" do
    [ order_path(@order), order_music_preview_path(@order) ].each do |path|
      get path
      assert_redirected_to order_chat_path(order_id: @order.id)
      refute_includes response.body, @asset.provider_url
    end
  end

  test "previews stream only the marked derivative with private caching and range support" do
    attach_audition
    get order_audio_preview_path(@order, asset_id: @asset.id)
    assert_response :success
    assert_equal "marked audition", response.body
    assert_includes response.headers["Cache-Control"], "no-store"
    refute response.headers["Location"]
    get order_audio_preview_path(@order, asset_id: @asset.id), headers: { "Range" => "bytes=0-5" }
    assert_response :partial_content
    assert_equal "marked", response.body
    get order_audio_preview_path(@order, asset_id: @asset.id), headers: { "Range" => "bytes=999-1000" }
    assert_response :range_not_satisfiable
    @asset.update!(preview_revision: 1)
    get order_audio_preview_path(@order, asset_id: @asset.id)
    assert_response :not_found
  end

  test "missing derivative never falls back to the clean recording" do
    get order_audio_preview_path(@order, asset_id: @asset.id)
    assert_response :not_found
    assert_nil @asset.campaign_playback_url
    assert_nil @asset.playback_url
    get order_audio_final_path(@order, asset_id: @asset.id)
    assert_response :not_found
  end

  test "only the approved asset in the approved round can be downloaded" do
    attach_audition
    older = @asset.dup
    older.music_generation = music_generations(:generation_completed)
    older.save!
    older.audio.attach(io: StringIO.new("other round"), filename: "other.mp3", content_type: "audio/mpeg")
    @order.update!(status: "approved", approved_variant: "a", approved_music_generation_id: @asset.music_generation_id)
    get order_audio_final_path(@order, asset_id: @asset.id)
    assert_response :success
    assert_equal "private original", response.body
    assert_includes response.headers["Cache-Control"], "no-store"
    assert_includes response.headers["Content-Disposition"], "attachment"
    [ order_assets(:music_variant_b), older ].each do |other|
      get order_audio_final_path(@order, asset_id: other.id)
      assert_response :not_found
    end
    assert Orders::MusicApprover.call(order: @order, asset_id: older.id).failure?
    get order_audio_preview_path(@order, asset_id: @asset.id)
    assert_response :success
    assert_equal "marked audition", response.body
    get rails_storage_proxy_path(@asset.audio)
    assert_response :not_found
  end

  test "anonymous and other customers cannot access previews or final downloads" do
    attach_audition
    @order.update!(status: "approved", approved_variant: "a", approved_music_generation_id: @asset.music_generation_id)
    paths = [ order_audio_preview_path(@order, asset_id: @asset.id), order_audio_final_path(@order, asset_id: @asset.id) ]
    sign_out :user
    paths.each { |path| get path; assert_response :redirect }
    sign_in users(:customer_other)
    get root_path # Persist the new login before requests that intentionally raise 404.
    assert_response :success
    paths.each { |path| get path; assert_response :not_found, path }
    get order_path(@order)
    assert_response :not_found
  end

  test "detached legacy excerpt links and representation aliases remain blocked" do
    blob = @asset.campaign_audio.blob
    @asset.campaign_audio.detach
    get rails_storage_proxy_path(blob)
    assert_response :not_found
    get rails_blob_path(blob)
    assert_response :not_found
    variation = ActiveStorage::Variation.encode(resize_to_limit: [ 100, 100 ])
    get rails_blob_representation_proxy_path(signed_blob_id: blob.signed_id, variation_key: variation, filename: blob.filename)
    assert_response :not_found
    get rails_blob_representation_proxy_path(signed_blob_id: blob.signed_id, variation_key: variation, filename: blob.filename), params: { signed_id: "invalid" }
    assert_response :not_found
  end

  test "public product photos still load through standard storage" do
    @campaign.photo.attach(io: StringIO.new("photo"), filename: "product.jpg", content_type: "image/jpeg")
    get rails_storage_proxy_path(@campaign.photo)
    assert_response :success
    assert_equal "photo", response.body
  end

  private

  def attach_audition
    @asset.audition_audio.attach(io: StringIO.new("marked audition"), filename: "audition.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: @asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
  end
end
