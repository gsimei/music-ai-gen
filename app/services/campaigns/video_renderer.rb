require "cgi"
require "open3"
require "timeout"
require "tmpdir"
require "net/http"
require "resolv"
require "ipaddr"

module Campaigns
  # Compose a real vertical MP4 locally. Photos and text never leave our renderer.
  class VideoRenderer
    def initialize(campaign)
      @campaign = campaign
    end

    def call
      raise "A música ainda não foi aprovada" unless @campaign.order.approved?
      Dir.mktmpdir("jinglepro-video-") do |dir|
        audio = File.join(dir, "music.mp3")
        download_audio(audio)
        visuals = make_visuals(dir)
        File.open(visuals.fetch(:poster)) do |file|
          @campaign.poster.attach(io: file, filename: "#{@campaign.order.reference}-arte.png", content_type: "image/png")
        end
        output = File.join(dir, "campaign.mp4")
        track_duration = Float(run!("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", audio))
        raise "Áudio inválido" unless track_duration.positive? && track_duration.finite?
        prepared = approved_audio_asset&.campaign_preview_ready?
        audio_start = prepared ? 0 : AudioExcerpt.start_seconds(lyrics_sync: approved_audio_asset&.lyrics_sync, track_duration: track_duration)
        duration = prepared ? approved_audio_asset.campaign_audio.blob.metadata.fetch("duration_seconds") : [track_duration - audio_start, 30].min
        audio_options = prepared ? ["-c:a", "copy"] : ["-af", "afade=t=out:st=#{[duration - 0.8, 0].max}:d=0.8", "-c:a", "aac", "-b:a", "192k"]
        audio_input = prepared ? ["-i", audio] : ["-ss", audio_start.to_s, "-i", audio]
        backgrounds = visuals.fetch(:backgrounds)
        count = backgrounds.size
        frames = (duration * 24).ceil
        transition_frames = [[(frames / (count * 2.0)).floor, 14].min, 1].max
        scene_frames = ((frames + (count - 1) * transition_frames).to_f / count).ceil
        scene_duration = scene_frames / 24.0
        transition_duration = transition_frames / 24.0
        # Only the photos transition. Offer and contact stay legible above them.
        filter = backgrounds.each_index.map do |index|
          zoom = index.even? ? "1.04+0.10*on/#{scene_frames}" : "1.14-0.10*on/#{scene_frames}"
          "[#{index}:v]scale=1440:2560,zoompan=z='#{zoom}':x='iw/2-iw/zoom/2+24*sin(on/#{scene_frames}*PI)':y='ih/2-ih/zoom/2':d=1:s=720x1280:fps=24,trim=duration=#{scene_duration},setpts=PTS-STARTPTS,settb=AVTB,setsar=1,format=yuv420p[photo#{index}]"
        end
        photo_stream = "photo0"
        (1...count).each do |index|
          offset = index * (scene_frames - transition_frames) / 24.0
          filter << "[#{photo_stream}][photo#{index}]xfade=transition=fade:duration=#{transition_duration}:offset=#{offset}[mix#{index}]"
          photo_stream = "mix#{index}"
        end
        offer_start = [1.5, duration * 0.05].min
        cta_start = [duration * 0.68, 20].min
        filter.concat([
          "[#{count}:v]format=rgba[brand]",
          "[#{count + 1}:v]format=rgba,fade=t=in:st=#{offer_start}:d=0.5:alpha=1[offer]",
          "[#{count + 2}:v]format=rgba,fade=t=in:st=#{cta_start}:d=0.5:alpha=1[cta]",
          "[#{photo_stream}][brand]overlay=0:0[branded]",
          "[branded][offer]overlay=x=0:y='720+36*max(0,1-(t-#{offer_start})/0.6)'[promotion]",
          "[promotion][cta]overlay=x=0:y='1050+24*max(0,1-(t-#{cta_start})/0.6)',format=yuv420p[video]"
        ])
        inputs = (backgrounds + visuals.values_at(:header, :offer, :cta)).flat_map { |path| ["-loop", "1", "-framerate", "24", "-i", path] }
        run!("ffmpeg", "-y", "-v", "error", *inputs, *audio_input,
          "-filter_complex_threads", "1", "-filter_complex", filter.join(";"),
          "-map", "[video]", "-map", "#{count + 3}:a:0", "-t", duration.to_s,
          *audio_options,
          "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
          "-movflags", "+faststart", "-threads", "2", output)
        File.open(output) do |file|
          @campaign.video.attach(io: file, filename: "#{@campaign.order.reference}-campanha.mp4", content_type: "video/mp4")
        end
      end
    end

    private

    def make_visuals(dir)
      photos = @campaign.product_photos
      raise "Escolha no máximo 5 fotos" if photos.size > 5
      backgrounds = photos.each_with_index.map do |image, index|
        path = File.join(dir, "background-#{index}.png")
        image.blob.open do |photo|
          run!(image_command, "-limit", "memory", "128MiB", "-limit", "map", "256MiB",
            "#{photo.path}[0]", "-auto-orient", "-resize", "1440x2560^", "-gravity", "center", "-extent", "1440x2560", path)
        end
        path
      end
      if backgrounds.empty?
        background = File.join(dir, "background.png")
        run!(image_command, "-size", "1440x2560", "gradient:#789644-#172619",
          "-fill", "#182310", "-draw", "circle 720,1040 1100,1040",
          "-fill", "#c1f66b", "-draw", "circle 720,1040 840,1040",
          "-fill", "#182310", "-draw", "circle 720,1040 736,1040", background)
        backgrounds << background
      end
      background = backgrounds.first
      header = svg_layer(dir, "header", 1280, <<~SVG)
        <rect x="56" y="90" width="42" height="5" rx="2" fill="#c1f66b"/>
        #{text_lines(@campaign.business_name, width: 26, x: 56, y: 151, size: 40, color: "#ffffff")}
      SVG
      shade = File.join(dir, "shade.png")
      run!(image_command, "-size", "720x360", "gradient:rgba(8,17,11,0.92)-rgba(8,17,11,0)", shade)
      run!(image_command, "-size", "720x1280", "xc:none", shade, "-geometry", "+0+0", "-composite", header, "-geometry", "+0+0", "-composite", header)
      price = @campaign.offer[/R\$\s*\d(?:[\d.,]*\d)?/]
      offer = svg_layer(dir, "offer", 320, <<~SVG)
        <rect x="36" y="0" width="648" height="320" rx="22" fill="#10170f" fill-opacity="0.94"/>
        <rect x="60" y="27" width="5" height="22" rx="2" fill="#c1f66b"/>
        <text x="79" y="44" font-size="17" fill="#c1f66b" letter-spacing="2">APROVEITE A OFERTA</text>
        #{text_lines(price, width: 22, x: 60, y: 119, size: 62, color: "#c1f66b") if price}
        #{text_lines(@campaign.offer, width: price ? 38 : 34, x: 60, y: price ? 167 : 96, size: price ? 26 : 30, color: "#ffffff", available_height: price ? 138 : 208)}
      SVG
      cta = svg_layer(dir, "cta", 140, <<~SVG)
        <rect x="36" y="0" width="648" height="130" rx="20" fill="#c1f66b"/>
        #{text_lines(@campaign.call_to_action, width: 40, x: 60, y: 36, size: 23, color: "#15200e", available_height: 52)}
        #{text_lines(@campaign.contact, width: 42, x: 60, y: 84, size: 21, color: "#15200e", available_height: 42)}
      SVG
      poster = File.join(dir, "poster.png")
      run!(image_command, background, "-resize", "720x1280!", header, "-geometry", "+0+0", "-composite",
        offer, "-geometry", "+0+720", "-composite", cta, "-geometry", "+0+1050", "-composite", poster)
      { backgrounds: backgrounds, header: header, offer: offer, cta: cta, poster: poster }
    end

    def svg_layer(dir, name, height, content)
      path = File.join(dir, "#{name}.svg")
      png = File.join(dir, "#{name}.png")
      font = RUBY_PLATFORM.include?("darwin") ? "Arial" : "DejaVu Sans"
      File.write(path, %(<svg xmlns="http://www.w3.org/2000/svg" width="720" height="#{height}"><g font-family="#{font}" font-weight="bold">#{content}</g></svg>))
      run!(image_command, "-background", "none", path, png)
      png
    end

    def text_lines(value, width:, x:, y:, size:, color:, available_height: nil)
      lines = wrap(value, width)
      size = [size, (available_height.to_f / lines.size - 7).floor].min if available_height && lines.any?
      # Keep unusually long uppercase names and handles within the safe area.
      widest = lines.map { |line| line.each_char.sum { |char| char.match?(/[MW@]/) ? 1.0 : (char.match?(/[A-Z]/) ? 0.8 : 0.65) } }.max || 1
      size = [size, (600 / [widest, 1].max).floor].min
      lines.each_with_index.map do |line, index|
        %(<text x="#{x}" y="#{y + index * (size + 7)}" font-size="#{size}" fill="#{color}">#{CGI.escapeHTML(line)}</text>)
      end.join
    end

    def wrap(text, width)
      words = text.to_s.gsub(/\s+/, " ").strip.split.flat_map { |word| word.scan(/.{1,#{width}}/m) }
      words.each_with_object([]) do |word, result|
        if result.empty? || result.last.length + word.length + 1 > width
          result << word
        else
          result[-1] += " #{word}"
        end
      end
    end

    def image_command
      @image_command ||= ENV.fetch("IMAGEMAGICK_BIN") do
        ENV.fetch("PATH").split(File::PATH_SEPARATOR).any? { |path| File.executable?(File.join(path, "magick")) } ? "magick" : "convert"
      end
    end

    def approved_audio_asset
      order = @campaign.order
      return unless %w[a b].include?(order.approved_variant)
      scope = order.order_assets.where(kind: "music_variant", variant_index: { "a" => 0, "b" => 1 }.fetch(order.approved_variant))
      scope = scope.where(music_generation_id: order.approved_music_generation_id) if order.approved_music_generation_id
      @approved_audio_asset ||= scope.order(id: :desc).first
    end

    def download_audio(destination)
      asset = approved_audio_asset || raise("A música aprovada não foi encontrada")
      if asset.campaign_preview_ready?
        asset.campaign_audio.blob.open { |file| FileUtils.cp(file.path, destination) }
      elsif asset.audio.attached?
        asset.audio.blob.open { |file| FileUtils.cp(file.path, destination) }
      else
        AudioDownload.call(asset.provider_url.presence || asset.url, destination)
      end
    rescue ActiveStorage::FileNotFoundError
      raise if asset.campaign_preview_ready? # Never replace the approved excerpt with a different cut.
      Rails.logger.warn "[Campaign video #{@campaign.id}] Archived audio missing; recovering from provider"
      ArchiveCampaignAudioJob.perform_later(asset.id)
      AudioDownload.call(asset.provider_url.presence || asset.url, destination)
    end

    def run!(*command)
      MediaCommand.run!(*command)
    end
  end
end
