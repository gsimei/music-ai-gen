require "test_helper"

class CampaignVideoPersonalizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @asset.audio.attach(io: StringIO.new("original"), filename: "original.mp3", content_type: "audio/mpeg")
    ready!
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  test "one minute and ninety second cuts use the archived recording without another musical round" do
    original = @asset.audio.blob.id
    [ 60, 90 ].each do |duration|
      revision = @asset.reload.preview_revision
      assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
        assert_enqueued_with(job: PrepareCampaignAudioJob, args: [ @asset.id, revision + 1 ]) do
          change_duration(duration, start: 10, revision: revision)
        end
      end
      assert_response :success
      assert_equal duration, @asset.reload.excerpt_duration_seconds
      assert_equal 10, @asset.excerpt_start_seconds
      assert_equal original, @asset.audio.blob.id
      refute @asset.campaign_preview_ready?
      assert_equal :preview_not_ready, Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: revision + 1).errors
      ready!(revision: revision + 1, duration: duration)
    end
  end

  test "the entire song starts at zero and custom cuts accept fractional durations" do
    change_duration("full", start: 1)
    assert_response :unprocessable_entity
    assert_equal 0, @asset.reload.preview_revision
    change_duration("full")
    assert_response :success
    assert_nil @asset.reload.excerpt_duration_seconds
    assert_equal 0, @asset.excerpt_max_start
    ready!(revision: 1, duration: 120.25)
    change_duration("custom", start: 2.5, custom: "72.75", revision: 1)
    assert_response :success
    assert_equal BigDecimal("72.75"), @asset.reload.excerpt_duration_seconds
    assert_equal BigDecimal("2.5"), @asset.excerpt_start_seconds
  end

  test "invalid lengths and cuts beyond the song leave the original preview intact" do
    [ "", "NaN", "Infinity", "wrong", -1, 0, 0.5, 120.26 ].each do |duration|
      assert_no_enqueued_jobs only: PrepareCampaignAudioJob do
        change_duration("custom", custom: duration)
      end
      assert_response :unprocessable_entity
      assert_equal 0, @asset.reload.preview_revision
      assert_equal 30, @asset.excerpt_duration_seconds
    end
    change_duration(90, start: 30.26)
    assert_response :unprocessable_entity
    change_duration(90, start: 30.25)
    assert_response :success
  end

  test "automatic reset restores the suggested short cut and stale tabs cannot approve a changed duration" do
    change_duration(90)
    ready!(revision: 1, duration: 90)
    assert_equal :stale_preview, Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 0).errors
    patch order_chat_excerpt_settings_path(order_id: @order.id), params: {
      asset_id: @asset.id, preview_revision: 1, automatic: "1", duration_seconds: "invalid", start_seconds: "invalid" }, headers: @headers
    assert_response :success
    assert_equal 30, @asset.reload.excerpt_duration_seconds
    assert_nil @asset.excerpt_start_seconds
  end

  test "new photos can be mixed with saved photos and keep the chosen order" do
    @campaign.photos.attach(upload("old1.png"), upload("old2.png"))
    previous = @campaign.product_photos
    original = @asset.audio.blob.id
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
      assert_no_enqueued_jobs only: RenderCampaignVideoJob do
        save_photos([ "upload:1", "saved:#{previous.last.id}", "upload:0" ], photos: [ upload("first.png"), upload("second.png") ])
      end
    end
    assert_response :success
    assert_equal [ "second.png", "old2.png", "first.png" ], @campaign.reload.product_photos.map { |image| image.filename.to_s }
    assert_equal 1, @campaign.video_revision
    assert_equal original, @asset.reload.audio.blob.id
    assert_equal 0, @asset.preview_revision
    assert_select "turbo-stream[target=?]", "campaign-summary-#{@campaign.id}"
  end

  test "saved photos can be reordered and removed including the original single photo" do
    @campaign.photo.attach(upload("legacy.png"))
    save_photos([ "" ])
    assert_response :success
    assert_empty @campaign.reload.product_photos
    refute @campaign.photo.attached?
    @campaign.photos.attach(upload("one.png"), upload("two.png"))
    ids = @campaign.reload.product_photos.map(&:id)
    save_photos(ids.reverse.map { |id| "saved:#{id}" }, revision: 1)
    assert_response :success
    assert_equal ids.reverse, @campaign.reload.product_photos.map(&:id)
  end

  test "unknown duplicated and unused photos cannot alter the composition" do
    @campaign.photos.attach(upload("saved.png"))
    photo = @campaign.product_photos.first
    another = Campaign.create!(order: orders(:b2b_paid), business_name: "Outra", offer: "Oferta",
      contact: "@outra", call_to_action: "Peça", style: "animado")
    another.photos.attach(upload("foreign.png"))
    [ [ "saved:#{another.product_photos.first.id}" ], [ "saved:#{photo.id}", "saved:#{photo.id}" ], [ "saved:unknown" ] ].each do |sequence|
      save_photos(sequence)
      assert_response :unprocessable_entity
      assert_equal [ photo.id ], @campaign.reload.product_photos.map(&:id)
      assert_equal 0, @campaign.video_revision
    end
    save_photos([ "saved:#{photo.id}" ], photos: [ upload("unused.png") ])
    assert_response :unprocessable_entity
    save_photos(Array.new(6) { |index| "upload:#{index}" }, photos: Array.new(6) { |index| upload("#{index}.png") })
    assert_response :unprocessable_entity
    assert_equal 0, @campaign.reload.video_revision
  end

  test "unsupported photos are rejected without replacing the saved images" do
    @campaign.photos.attach(upload("saved.png"))
    original = @campaign.product_photos.first.id
    bad = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "text/plain", original_filename: "bad.txt")
    save_photos([ "upload:0" ], photos: [ bad ])
    assert_response :unprocessable_entity
    assert_equal [ original ], @campaign.reload.product_photos.map(&:id)
    assert_equal 0, @campaign.video_revision
  end

  test "photo revisions protect approval and approved compositions are immutable" do
    save_photos([ "upload:0" ], photos: [ upload("new.png") ])
    assert_response :success
    save_photos([ "" ], revision: 0)
    assert_response :unprocessable_entity
    assert_equal :stale_video, Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 0).errors
    post order_chat_approve_music_path(order_id: @order.id), params: {
      asset_id: @asset.id, preview_revision: 0, video_revision: 1 }, headers: @headers
    assert_response :see_other
    assert @order.reload.approved?
    save_photos([ "" ], revision: 1)
    assert_response :unprocessable_entity
    assert_equal "new.png", @campaign.reload.product_photos.first.filename.to_s
    change_duration("full")
    assert_response :unprocessable_entity
  end

  test "another customer cannot edit the photos and studio exposes the available durations" do
    @campaign.update!(selected_music_asset: @asset)
    get order_chat_path(order_id: @order.id)
    assert_response :success
    assert_select '.ui-duration button[name=duration_seconds][value="90"]', text: /1 min 30/
    assert_select ".ui-duration button[name=duration_seconds][value=full]", text: /Música inteira 2:00/
    assert_select "#chat-lyrics-panel select", count: 0
    assert_select "form[action=?]", order_chat_video_photos_path(order_id: @order.id)
    sign_out :user
    sign_in users(:customer_other)
    save_photos([ "" ])
    assert_response :not_found
  end

  test "a two minute video accepts twenty photos in order without spending a musical round" do
    @campaign.update!(selected_music_asset: @asset)
    change_duration("full")
    ready!(revision: 1, duration: 120.25)
    assert_equal 20, @campaign.reload.photo_limit
    files = Array.new(20) { |index| upload("photo-#{index}.png") }
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
      save_photos(Array.new(20) { |index| "upload:#{index}" }, photos: files)
    end
    assert_response :success
    assert_equal files.map(&:original_filename), @campaign.reload.product_photos.map { |photo| photo.filename.to_s }
    assert_select 'form#video-photos[data-video-photos-limit-value="20"]'
    assert_select "#video-photos .ui-slot", count: 20
    assert_select "#video-photos .ui-slot-empty", count: 0
    previous_ids = @campaign.product_photos.map(&:id)
    save_photos([ *previous_ids.map { |id| "saved:#{id}" }, "upload:0" ], photos: [ upload("extra.png") ], revision: 1)
    assert_response :unprocessable_entity
    assert_equal previous_ids, @campaign.reload.product_photos.map(&:id)
  end

  test "each version must fit the saved photos even if another version allows more" do
    change_duration("full")
    ready!(revision: 1, duration: 120.25)
    other = order_assets(:music_variant_b)
    ready!(asset: other)
    save_photos(Array.new(20) { |index| "upload:#{index}" }, photos: Array.new(20) { |index| upload("#{index}.png") })
    assert_response :success
    assert_no_enqueued_jobs only: RenderCampaignVideoJob do
      post order_chat_approve_music_path(order_id: @order.id), params: {
        asset_id: other.id, preview_revision: 0, video_revision: 1 }, headers: @headers
    end
    assert_response :unprocessable_entity
    assert @order.reload.preview_ready?
    @campaign.update!(selected_music_asset: other)
    get order_chat_path(order_id: @order.id)
    assert_select "form[action=?] button[disabled]", order_chat_approve_music_path(order_id: @order.id), text: "Gerar meu vídeo"
    @campaign.update!(selected_music_asset: @asset)
    get order_chat_path(order_id: @order.id)
    assert_select "form[action=?] button:not([disabled])", order_chat_approve_music_path(order_id: @order.id), text: "Gerar meu vídeo"
    post order_chat_approve_music_path(order_id: @order.id), params: {
      asset_id: @asset.id, preview_revision: 1, video_revision: 1 }, headers: @headers
    assert_response :see_other
    assert @order.reload.approved?
    assert_equal 20, @campaign.reload.photo_limit
  end

  test "shortening the video preserves saved photos and asks for fewer before approval" do
    change_duration("full")
    ready!(revision: 1, duration: 120.25)
    save_photos(Array.new(10) { |index| "upload:#{index}" }, photos: Array.new(10) { |index| upload("#{index}.png") })
    ids = @campaign.reload.product_photos.map(&:id)
    change_duration(30, revision: 1)
    ready!(revision: 2)
    assert_equal ids, @campaign.reload.product_photos.map(&:id)
    assert @campaign.valid?, "Saved photos must not invalidate unrelated updates when a cut gets shorter"
    assert_equal 5, @campaign.photo_limit
    assert_equal :photos_exceed_duration, Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 2, video_revision: 1).errors
    save_photos(ids.first(5).map { |id| "saved:#{id}" }, revision: 1)
    assert_response :success
    assert_equal ids.first(5), @campaign.reload.product_photos.map(&:id)
    assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 2, video_revision: 2).success?
  end

  test "the longest videos are capped at thirty photos" do
    @asset.update!(excerpt_duration_seconds: nil)
    ready!(duration: 300, track_duration: 300)
    assert_equal 30, @campaign.reload.photo_limit
    save_photos(Array.new(31) { |index| "upload:#{index}" }, photos: Array.new(31) { |index| upload("#{index}.png") })
    assert_response :unprocessable_entity
    assert_empty @campaign.reload.product_photos
    save_photos(Array.new(30) { |index| "upload:#{index}" }, photos: Array.new(30) { |index| upload("#{index}.png") })
    assert_response :success
    assert_equal 30, @campaign.reload.product_photos.size
  end

  private

  def upload(name)
    Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png", true, original_filename: name)
  end

  def change_duration(duration, start: 0, custom: nil, revision: 0)
    patch order_chat_excerpt_settings_path(order_id: @order.id), params: {
      asset_id: @asset.id, preview_revision: revision, duration_seconds: duration,
      custom_duration_seconds: custom, start_seconds: start }, headers: @headers
  end

  def save_photos(sequence, photos: [], revision: 0)
    patch order_chat_video_photos_path(order_id: @order.id), params: {
      video_revision: revision, photos: photos, photo_sequence: sequence }, headers: @headers
  end

  def ready!(revision: 0, duration: 30, track_duration: 120.25, asset: @asset)
    asset.reload.campaign_audio.attach(io: StringIO.new("excerpt #{revision}"), filename: "excerpt.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: revision, duration_seconds: duration, track_duration_seconds: track_duration, start_seconds: 0 })
    asset.audition_audio.attach(io: StringIO.new("protected"), filename: "audition.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: revision, watermark_version: Campaigns::AudioAudition::VERSION })
    asset.update!(campaign_preview_status: "ready")
  end
end
