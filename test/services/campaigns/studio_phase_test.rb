require "test_helper"

class Campaigns::StudioPhaseTest < ActiveSupport::TestCase
  def order_with(status, video_status: "pending", selected: false)
    order = orders(:b2b_pending)
    order.update_columns(status: status)
    campaign = Campaign.create!(order: order, business_name: "Pizzaria", offer: "Oferta", contact: "@pizza",
      call_to_action: "Peça agora", style: "animado", video_status: video_status)
    campaign.update_columns(selected_music_asset_id: order_assets(:music_variant_a).id) if selected
    order.reload
  end

  %w[paid lyrics_drafting lyrics_ready lyrics_failed].each do |status|
    test "#{status} is the lyrics phase" do
      assert_equal :lyrics, Campaigns::StudioPhase.for(order_with(status))
    end
  end

  %w[lyrics_approved music_generating].each do |status|
    test "#{status} is the music phase" do
      assert_equal :music, Campaigns::StudioPhase.for(order_with(status))
    end
  end

  %w[preview_ready music_failed].each do |status|
    test "#{status} without a selected music is the music phase" do
      assert_equal :music, Campaigns::StudioPhase.for(order_with(status))
    end

    test "#{status} with a selected music is the video phase" do
      assert_equal :video, Campaigns::StudioPhase.for(order_with(status, selected: true))
    end
  end

  %w[pending queued rendering].each do |video_status|
    test "approved with video #{video_status} is the rendering phase" do
      assert_equal :rendering, Campaigns::StudioPhase.for(order_with("approved", video_status: video_status))
    end
  end

  test "approved with a failed video is the failed_video phase" do
    assert_equal :failed_video, Campaigns::StudioPhase.for(order_with("approved", video_status: "failed"))
  end

  test "approved with a ready video is the delivered phase" do
    assert_equal :delivered, Campaigns::StudioPhase.for(order_with("approved", video_status: "ready"))
  end

  %w[pending cancelled refunded payment_failed].each do |status|
    test "#{status} has no phase" do
      assert_nil Campaigns::StudioPhase.for(order_with(status))
    end
  end

  test "an order without a campaign has no phase" do
    order = orders(:b2b_paid)
    assert_nil order.campaign
    assert_nil Campaigns::StudioPhase.for(order)
  end

  test "step maps phases to the progress bar" do
    assert_equal 1, Campaigns::StudioPhase.step(:lyrics)
    assert_equal 2, Campaigns::StudioPhase.step(:music)
    assert_equal 3, Campaigns::StudioPhase.step(:video)
    assert_equal 3, Campaigns::StudioPhase.step(:rendering)
    assert_equal 3, Campaigns::StudioPhase.step(:failed_video)
    assert_equal 4, Campaigns::StudioPhase.step(:delivered)
    assert_nil Campaigns::StudioPhase.step(nil)
  end
end
