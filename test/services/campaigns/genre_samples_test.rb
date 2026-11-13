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

  # O cartão do player (tarefa 6 do plano "caminho B") mostra a duração antes de o áudio carregar:
  # ela vem do catálogo, que a lê do manifesto. Nada de "12 segundos" escrito na view.
  test "every catalog item carries the duration_seconds of its manifest record" do
    catalog = Campaigns::GenreSamples.catalog
    assert_not_empty catalog
    manifest = JSON.parse(Rails.root.join("config/genre_samples.json").read)
    catalog.each do |key, sample|
      assert sample.key?(:duration_seconds), "#{key}: o catálogo precisa expor duration_seconds"
      assert_kind_of Numeric, sample.fetch(:duration_seconds), key
      assert_in_delta 12, sample.fetch(:duration_seconds), 0.5, key
      assert_equal manifest.fetch("samples").fetch(key).fetch("duration_seconds").to_f, sample.fetch(:duration_seconds).to_f, key
      assert_equal %i[duration_seconds label url], sample.keys.sort, "#{key}: chaves do item do catálogo"
    end
  end
end
