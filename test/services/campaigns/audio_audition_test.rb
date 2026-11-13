require "test_helper"
require "tmpdir"
require "open3"

class Campaigns::AudioAuditionTest < ActiveSupport::TestCase
  test "the same seed gives the same offset and gain" do
    assert_equal Campaigns::AudioAudition.mark_params("42"), Campaigns::AudioAudition.mark_params("42")
  end

  test "different seeds give different offsets and gains" do
    params = %w[1 2 3 4 5].map { |seed| Campaigns::AudioAudition.mark_params(seed) }
    assert_equal 5, params.map(&:first).uniq.size
    assert_equal 5, params.map { |p| p[1] }.uniq.size
  end

  test "offset stays inside one period and gain inside the jitter band" do
    100.times do |seed|
      offset, gain = Campaigns::AudioAudition.mark_params(seed.to_s)
      assert_operator offset, :>=, 0
      assert_operator offset, :<, Campaigns::AudioAudition::PERIOD
      assert_includes 1.5..2.1, gain
    end
  end

  test "period is short enough and VERSION re-renders old derivatives" do
    assert_operator Campaigns::AudioAudition::PERIOD, :<=, 3.5
    assert_operator Campaigns::AudioAudition::VERSION, :>=, 2
  end

  test "a marked silent source has no silent stretch and no unmarked gap longer than 3.6 s" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "silence.wav")
      destination = File.join(dir, "marked.m4a")
      Campaigns::MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", "20", source)
      Campaigns::AudioAudition.render(source: source, destination: destination, start_seconds: 5, duration_seconds: 20, seed: "7")
      assert_empty silences(destination, "-70dB", 0.5), "The noise bed must leave no fully clean stretch"
      gaps = silences(destination, "-40dB", 0.1)
      assert_operator gaps.max || 0, :<=, 3.6, "Unmarked gaps: #{gaps.inspect}"
    end
  end

  private

  # Durations of every stretch below `noise` lasting at least `min` seconds.
  def silences(path, noise, min)
    out, = Open3.capture2e("ffmpeg", "-v", "info", "-nostats", "-i", path,
      "-af", "silencedetect=noise=#{noise}:d=#{min}", "-f", "null", "-")
    out.scan(/silence_duration: ([\d.]+)/).flatten.map(&:to_f)
  end
end
