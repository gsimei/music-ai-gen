require "test_helper"

class CampaignExcerptTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @asset.audio.attach(io: StringIO.new("original"), filename: "original.mp3", content_type: "audio/mpeg")
    ready!(0)
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  test "merchant can request a fractional cut without spending a musical round and must audition the new revision" do
    original = @asset.audio.blob.id
    previous = @asset.campaign_audio.blob.id
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count" ] do
      assert_enqueued_with(job: PrepareCampaignAudioJob, args: [ @asset.id, 1 ]) { change(10.25) }
    end
    assert_response :success
    assert_equal BigDecimal("10.25"), @asset.reload.excerpt_start_seconds
    assert_equal 1, @asset.preview_revision
    assert_equal "queued", @asset.campaign_preview_status
    assert_equal previous, @asset.campaign_audio.blob.id
    assert_equal original, @asset.audio.blob.id
    refute @asset.campaign_preview_ready?
    assert_equal :preview_not_ready, Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 1).errors
    ready!(1)
    assert_equal :stale_preview, Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 0).errors
    assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 1).success?
    change(0, revision: 1)
    assert_response :unprocessable_entity
    assert_equal BigDecimal("10.25"), @asset.reload.excerpt_start_seconds
  end

  test "invalid starts and other customers assets cannot change the audio" do
    [ -1, 30.01, "NaN", "Infinity", "", "texto" ].each do |invalid|
      change(invalid)
      assert_response :unprocessable_entity
      assert_equal 0, @asset.reload.preview_revision
    end
    change(0, revision: 99)
    assert_response :unprocessable_entity
    sign_out :user
    sign_in users(:customer_other)
    change(10)
    assert_response :not_found
    assert_equal 0, @asset.reload.preview_revision
  end

  test "both boundaries are valid and automatic reset remains available" do
    change(30)
    assert_response :success
    ready!(1)
    change(0, revision: 1)
    assert_response :success
    ready!(2)
    patch order_chat_excerpt_settings_path(order_id: @order.id), params: { asset_id: @asset.id, preview_revision: 2, automatic: "1", start_seconds: "invalid" }, headers: @headers
    assert_response :success
    assert_nil @asset.reload.excerpt_start_seconds
    assert_equal 3, @asset.preview_revision
  end

  test "a queued cut cannot be changed twice and an outdated worker cannot replace it" do
    change(5)
    assert_response :success
    change(15, revision: 1)
    assert_response :unprocessable_entity
    assert_equal BigDecimal("5"), @asset.reload.excerpt_start_seconds
    Campaigns::AudioPreview.stub(:render, ->(**_) { flunk "Stale worker must not render" }) do
      assert_no_difference("ActiveStorage::Blob.count") { PrepareCampaignAudioJob.perform_now(@asset.id, 0) }
    end
    assert_equal "queued", @asset.reload.campaign_preview_status
  end

  private

  def change(start, revision: 0)
    patch order_chat_excerpt_settings_path(order_id: @order.id), params: {
      asset_id: @asset.id, preview_revision: revision, start_seconds: start }, headers: @headers
  end

  def ready!(revision)
    @asset.reload
    @asset.campaign_audio.attach(io: StringIO.new("excerpt #{revision}"), filename: "excerpt.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: revision, duration_seconds: 30, track_duration_seconds: 60, start_seconds: 0 })
    @asset.update!(campaign_preview_status: "ready")
  end
end
