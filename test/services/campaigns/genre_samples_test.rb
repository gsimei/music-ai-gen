require "test_helper"
require "digest"

class Campaigns::GenreSamplesTest < ActiveSupport::TestCase
  test "every offered rhythm has a complete reusable twelve second audio asset" do
    catalog = Campaigns::GenreSamples.catalog
    assert_equal Campaign::GENRES.except("auto").keys.sort, catalog.keys.sort
    manifest = JSON.parse(Rails.root.join("config/genre_samples.json").read)
    catalog.each do |key, sample|
      path = Rails.root.join("public", sample.fetch(:url).delete_prefix("/"))
      record = manifest.fetch("samples").fetch(key)
      assert_equal record.fetch("sha256"), Digest::SHA256.file(path).hexdigest
      metadata = JSON.parse(Campaigns::MediaCommand.run!("ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_name", "-of", "json", path.to_s))
      assert_in_delta 12, metadata.fetch("format").fetch("duration").to_f, 0.1
      assert_equal "mp3", metadata.fetch("streams").first.fetch("codec_name")
      assert_equal "mureka-9", record.fetch("model")
      assert_equal 1, record.fetch("n")
    end
  end
end
