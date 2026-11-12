require "test_helper"

class Campaigns::PhotoLimitTest < ActiveSupport::TestCase
  test "longer videos allow more photos with a ceiling and stable limits near whole seconds" do
    { 5 => 5, 30 => 5, 45 => 7, 60 => 10, 90 => 15, 119.99 => 20, 120.25 => 20, 180 => 30, 300 => 30 }.each do |duration, limit|
      assert_equal limit, Campaigns::PhotoLimit.for_duration(duration), "Duration: #{duration}"
    end
    [ nil, "bad", "NaN", Float::INFINITY, -30 ].each do |duration|
      assert_equal 5, Campaigns::PhotoLimit.for_duration(duration)
    end
  end

  test "the limit uses the prepared cut rather than the full source duration" do
    asset = order_assets(:music_variant_a)
    asset.update!(duration_ms: 180000)
    asset.campaign_audio.attach(io: StringIO.new("audio"), filename: "cut.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: 0, duration_seconds: 60, track_duration_seconds: 180 })
    asset.update!(campaign_preview_status: "ready")
    assert_equal 10, Campaigns::PhotoLimit.for_asset(asset)
    asset.update!(excerpt_duration_seconds: nil, preview_revision: 1, campaign_preview_status: "queued")
    assert_equal 30, Campaigns::PhotoLimit.for_asset(asset)
  end
end
