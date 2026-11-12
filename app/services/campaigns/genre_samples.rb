module Campaigns
  class GenreSamples
    # Listening only serves these static assets. It never invokes a generation API.
    def self.catalog
      manifest_path = Rails.root.join("config/genre_samples.json")
      return {} unless manifest_path.file?
      samples = JSON.parse(manifest_path.read).fetch("samples", {})
      Campaign::GENRES.except("auto").filter_map do |key, genre|
        file = "/demos/genres/#{key}-v1.mp3"
        next unless samples.dig(key, "status") == "ready"
        next unless Rails.root.join("public", file.delete_prefix("/")).file?
        [ key, { url: file, label: genre.fetch(:label).split(" · ").first } ]
      end.to_h
    rescue JSON::ParserError
      Rails.logger.warn("Genre sample manifest is invalid; examples temporarily unavailable")
      {}
    end
  end
end
