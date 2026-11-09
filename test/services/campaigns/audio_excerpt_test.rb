require "test_helper"

class Campaigns::AudioExcerptTest < ActiveSupport::TestCase
  test "skips the intro so all vocal lines and the offer fit in the video" do
    timing = { "sections" => [section("verse", 15440, 28920), section("chorus", 29440, 41920)] }
    start = Campaigns::AudioExcerpt.start_seconds(lyrics_sync: timing, track_duration: 54.03)
    assert_in_delta 15.19, start, 0.001
    assert_operator start + 29.2, :>, 41.92
  end

  test "prefers a complete chorus when the entire vocal performance exceeds thirty seconds" do
    timing = { "sections" => [section("verse", 1000, 35000), section("chorus", 36000, 55000)] }
    assert_in_delta 35.75, Campaigns::AudioExcerpt.start_seconds(lyrics_sync: timing, track_duration: 60), 0.001
  end

  test "missing or invalid timing keeps the original beginning" do
    [nil, [], {}, { "sections" => [nil, section("verse", -1, 1000), section("verse", 2000, 90000), section("verse", "bad", 3000)] }].each do |timing|
      assert_equal 0, Campaigns::AudioExcerpt.start_seconds(lyrics_sync: timing, track_duration: 30)
    end
  end

  private

  def section(type, start_at, end_at)
    { "section_type" => type, "lines" => [{ "start" => start_at, "end" => end_at }] }
  end
end
