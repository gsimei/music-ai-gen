# Run through `rails runner` inside the production image, without databases,
# credentials, external requests, or customer files. Exercises the real renderer.
require "rack/mock"
require "tmpdir"

raise "Use production with SECRET_KEY_BASE_DUMMY=1" unless Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].present?

module ProductionSmoke
  class Attachment
    attr_reader :data

    def attach(io:, **)
      @data = io.read
    end

    def attached? = false
  end

  Order = Struct.new(:reference, :approved_variant) { def approved? = true }
  Blob = Struct.new(:content_type, :path) { def open; File.open(path) { |file| yield file }; end }
  Photo = Struct.new(:blob)
  Campaign = Struct.new(:order, :business_name, :offer, :contact, :call_to_action, :product_photos, :poster, :video, :id) do
    def logo = Attachment.new
    def show_cta? = true
    def cta_background_color = "#d6f36b"
    def cta_text_color = "#173e32"
  end

  def self.run
    host = Rails.application.config.x.public_host
    status, headers, body = Rails.application.call(Rack::MockRequest.env_for("https://#{host}/", "HTTP_HOST" => host))
    body.close if body.respond_to?(:close)
    raise "Web boot failed: #{status}" unless status == 200
    raise "CSP missing" unless headers["content-security-policy"].include?("nonce-")
    raise "HSTS missing" unless headers["strict-transport-security"]

    Dir.mktmpdir("production-smoke-") do |dir|
      photos = %w[jpeg png webp].map do |format|
        path = File.join(dir, "photo.#{format}")
        Campaigns::MediaCommand.run!("convert", "-size", "100x180", "xc:#c1f66b", path)
        Photo.new(Blob.new("image/#{format}", path))
      end
      campaign = Campaign.new(Order.new("SMOKE", nil), "Café & Pão", "Café por R$ 12 nesta terça", "@cafe", "Venha nos visitar",
        photos, Attachment.new, Attachment.new, 0)
      renderer = Campaigns::VideoRenderer.new(campaign)
      renderer.define_singleton_method(:download_audio) do |destination|
        Campaigns::MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", destination)
      end
      renderer.call
      video = File.join(dir, "result.mp4")
      File.binwrite(video, campaign.video.data)
      info = JSON.parse(Campaigns::MediaCommand.run!("ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height", "-of", "json", video))
      unless info["streams"].any? { |stream| stream["codec_name"] == "h264" && stream["width"] == 720 && stream["height"] == 1280 }
        raise "Invalid video dimensions or codec"
      end
      raise "No AAC audio" unless info["streams"].any? { |stream| stream["codec_name"] == "aac" }
      raise "Image must run as an unprivileged user" if Process.uid.zero?

      puts JSON.generate(rails: Rails.version, uid: Process.uid, app_status: status,
        rendered_bytes: campaign.video.data.bytesize, photo_formats: %w[jpeg png webp], codecs: info["streams"].map { |stream| stream["codec_name"] })
    end
  end
end

ProductionSmoke.run
