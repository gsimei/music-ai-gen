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
    PHOTO_CODERS = { "image/jpeg" => "JPEG", "image/png" => "PNG", "image/webp" => "WEBP" }.freeze
    FRAME_HEIGHT = 1280
    BOTTOM_MARGIN = 36
    CARD_GAP = 12
    CTA_HEIGHT = 130
    def initialize(campaign)
      @campaign = campaign
    end

    def call
      raise "A música ainda não foi aprovada" unless @campaign.order.approved?
      Dir.mktmpdir("jinglepro-video-") do |dir|
        audio = File.join(dir, "music.mp3")
        download_audio(audio)
        output = File.join(dir, "campaign.mp4")
        track_duration = Float(run!("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", audio))
        raise "Áudio inválido" unless track_duration.positive? && track_duration.finite?
        prepared = approved_audio_asset&.campaign_preview_ready?
        audio_start = prepared ? 0 : AudioExcerpt.start_seconds(lyrics_sync: approved_audio_asset&.lyrics_sync, track_duration: track_duration)
        duration = prepared ? approved_audio_asset.campaign_audio.blob.metadata.fetch("duration_seconds") : [ track_duration - audio_start, 30 ].min
        visuals = make_visuals(dir, photo_limit: PhotoLimit.for_duration(duration))
        File.open(visuals.fetch(:poster)) do |file|
          @campaign.poster.attach(io: file, filename: "#{@campaign.order.reference}-arte.png", content_type: "image/png")
        end
        audio_options = prepared ? [ "-c:a", "copy" ] : [ "-af", "afade=t=out:st=#{[ duration - 0.8, 0 ].max}:d=0.8", "-c:a", "aac", "-b:a", "192k" ]
        audio_input = prepared ? [ "-i", audio ] : [ "-ss", audio_start.to_s, "-i", audio ]
        backgrounds = visuals.fetch(:backgrounds)
        count = backgrounds.size
        frames = (duration * 24).ceil
        transition_frames = [ [ (frames / (count * 2.0)).floor, 14 ].min, 1 ].max
        scene_frames = ((frames + (count - 1) * transition_frames).to_f / count).ceil
        scene_duration = scene_frames / 24.0
        transition_duration = transition_frames / 24.0
        # Only the photos transition. Offer and contact stay legible above them.
        filter = backgrounds.each_index.map do |index|
          zoom = index.even? ? "1.04+0.10*on/#{scene_frames}" : "1.14-0.10*on/#{scene_frames}"
          "[#{index}:v]scale=1440:2560,zoompan=z='#{zoom}':x='iw/2-iw/zoom/2+24*sin(on/#{scene_frames}*PI)':y='ih/2-ih/zoom/2':d=1:s=720x1280:fps=24,trim=duration=#{scene_duration},setpts=PTS-STARTPTS,fps=24,settb=AVTB,setsar=1,format=yuv420p[photo#{index}]"
        end
        photo_stream = "photo0"
        (1...count).each do |index|
          offset = index * (scene_frames - transition_frames) / 24.0
          # FFmpeg 7 clears the reported frame rate on xfade output. Restore
          # both rate and time base before feeding another transition.
          filter << "[#{photo_stream}][photo#{index}]xfade=transition=fade:duration=#{transition_duration}:offset=#{offset},fps=24,settb=AVTB[mix#{index}]"
          photo_stream = "mix#{index}"
        end
        offer_start = [ 1.5, duration * 0.05 ].min
        filter.concat([
          "[#{count}:v]format=rgba[brand]",
          "[#{count + 1}:v]format=rgba,fade=t=in:st=#{offer_start}:d=0.5:alpha=1[offer]",
          "[#{photo_stream}][brand]overlay=0:0[branded]",
          "[branded][offer]overlay=x=0:y='#{visuals.fetch(:offer_y)}+36*max(0,1-(t-#{offer_start})/0.6)'[promotion]"
        ])
        if visuals[:cta]
          cta_start = [ duration * 0.68, 20 ].min
          filter << "[#{count + 2}:v]format=rgba,fade=t=in:st=#{cta_start}:d=0.5:alpha=1[cta]"
          filter << "[promotion][cta]overlay=x=0:y='#{visuals.fetch(:cta_y)}+24*max(0,1-(t-#{cta_start})/0.6)',format=yuv420p[video]"
        else
          filter << "[promotion]format=yuv420p[video]"
        end
        # Static photos need only one decoder thread, even in larger slideshows.
        image_inputs = backgrounds + visuals.values_at(:header, :offer, :cta).compact
        inputs = image_inputs.flat_map { |path| [ "-loop", "1", "-framerate", "24", "-threads", "1", "-i", path ] }
        run!("ffmpeg", "-y", "-v", "error", *inputs, *audio_input,
          "-filter_complex_threads", "1", "-filter_complex", filter.join(";"),
          "-map", "[video]", "-map", "#{image_inputs.size}:a:0", "-t", duration.to_s,
          *audio_options,
          "-c:v", "libx264", "-preset", "veryfast", "-crf", "22",
          "-movflags", "+faststart", "-threads", "2", output, timeout: [ 180, (duration * 8).ceil ].max)
        File.open(output) do |file|
          @campaign.video.attach(io: file, filename: "#{@campaign.order.reference}-campanha.mp4", content_type: "video/mp4",
            metadata: { duration_seconds: duration })
        end
      end
    end

    private

    def make_visuals(dir, photo_limit: PhotoLimit::MAX)
      photos = @campaign.product_photos
      raise "Esta duração permite no máximo #{photo_limit} fotos" if photos.size > photo_limit
      backgrounds = photos.each_with_index.map do |image, index|
        path = File.join(dir, "background-#{index}.png")
        image.blob.open do |photo|
          # Never let uploaded bytes select SVG/MVG or other ImageMagick coders.
          # These raw commands do not inherit Active Storage's MiniMagick policy.
          coder = PHOTO_CODERS.fetch(image.blob.content_type) { raise "Formato de foto não permitido" }
          run!(image_command, "-limit", "memory", "128MiB", "-limit", "map", "256MiB",
            "#{coder}:#{photo.path}[0]", "-auto-orient", "-resize", "1440x2560^", "-gravity", "center", "-extent", "1440x2560", path)
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
      has_logo = @campaign.logo.attached?
      header = svg_layer(dir, "header", 1280, <<~SVG)
        #{'<rect x="56" y="90" width="42" height="5" rx="2" fill="#c1f66b"/>' if @campaign.business_name.present? && !has_logo}
        #{text_lines(@campaign.business_name, width: 26, x: 56, y: has_logo ? 290 : 151, size: 40, color: "#ffffff", available_height: has_logo ? 65 : 175) if @campaign.business_name.present?}
      SVG
      shade = File.join(dir, "shade.png")
      run!(image_command, "-size", "720x360", "gradient:rgba(8,17,11,0.92)-rgba(8,17,11,0)", shade)
      run!(image_command, "-size", "720x1280", "xc:none", shade, "-geometry", "+0+0", "-composite", header, "-geometry", "+0+0", "-composite", header)
      if has_logo
        logo = File.join(dir, "business-logo.png")
        @campaign.logo.blob.open do |file|
          coder = PHOTO_CODERS.fetch(@campaign.logo.blob.content_type) { raise "Formato de logo não permitido" }
          run!(image_command, "-limit", "memory", "128MiB", "-limit", "map", "256MiB",
            "#{coder}:#{file.path}[0]", "-auto-orient", "-resize", "260x160", logo)
        end
        run!(image_command, header, logo, "-geometry", "+56+80", "-composite", header)
      end
      offer_lines, offer_size = text_layout(@campaign.offer, width: 34, size: 30, available_height: 208)
      # Match the panel to the rendered baselines, including descenders and padding.
      offer_height = (96 + (offer_lines.size - 1) * offer_size * 1.25 + offer_size * 0.25 + 24).ceil
      cta_y = FRAME_HEIGHT - BOTTOM_MARGIN - CTA_HEIGHT if @campaign.show_cta?
      offer_y = (cta_y ? cta_y - CARD_GAP : FRAME_HEIGHT - BOTTOM_MARGIN) - offer_height
      offer = svg_layer(dir, "offer", offer_height, <<~SVG)
        <rect x="36" y="0" width="648" height="#{offer_height}" rx="22" fill="#10170f" fill-opacity="0.94"/>
        <rect x="60" y="27" width="5" height="22" rx="2" fill="#c1f66b"/>
        <text x="79" y="44" font-size="17" fill="#c1f66b" letter-spacing="2">APROVEITE A OFERTA</text>
        #{text_lines(@campaign.offer, width: 34, x: 60, y: 96, size: 30, color: "#ffffff", available_height: 208)}
      SVG
      if @campaign.show_cta?
        cta = svg_layer(dir, "cta", CTA_HEIGHT, <<~SVG)
          <rect x="36" y="0" width="648" height="#{CTA_HEIGHT}" rx="20" fill="#{@campaign.cta_background_color}"/>
          #{text_lines(@campaign.call_to_action, width: 40, x: 60, y: 36, size: 23, color: @campaign.cta_text_color, available_height: 52)}
          #{text_lines(@campaign.contact, width: 42, x: 60, y: 84, size: 21, color: @campaign.cta_text_color, available_height: 42)}
        SVG
      end
      poster = File.join(dir, "poster.png")
      layers = [ header, "-geometry", "+0+0", "-composite", offer, "-geometry", "+0+#{offer_y}", "-composite" ]
      layers.concat([ cta, "-geometry", "+0+#{cta_y}", "-composite" ]) if cta
      run!(image_command, background, "-resize", "720x1280!", *layers, poster)
      { backgrounds: backgrounds, header: header, offer: offer, cta: cta, poster: poster, offer_y: offer_y, cta_y: cta_y }
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
      lines, size = text_layout(value, width: width, size: size, available_height: available_height)
      lines.each_with_index.map do |line, index|
        %(<text x="#{x}" y="#{(y + index * size * 1.25).round(2)}" font-size="#{size}" fill="#{color}" xml:space="preserve">#{CGI.escapeHTML(line)}</text>)
      end.join
    end

    def text_layout(value, width:, size:, available_height: nil)
      lines = wrap(value, width)
      size = [ size, available_height.to_f / (lines.size * 1.25) ].min if available_height && lines.any?
      # Keep unusually long uppercase names and handles within the safe area.
      widest = lines.map { |line| line.each_char.sum { |char| char.match?(/[MW@]/) ? 1.0 : (char.match?(/[A-Z]/) ? 0.8 : 0.65) } }.max || 1
      size = [ size, 600.0 / [ widest, 1 ].max ].min.round(2)
      [ lines, size ]
    end

    def wrap(text, width)
      DisplayText.call(text).split("\n", -1).flat_map do |paragraph|
        words = paragraph.strip.split(/[ \t\f\v]+/).flat_map do |word|
          # Keep a currency and its amount together, even on a narrow line.
          word.start_with?("R$\u00a0") ? [ word ] : word.scan(/.{1,#{width}}/m)
        end
        next [ "" ] if words.empty?
        words.each_with_object([]) do |word, result|
          if result.empty? || result.last.length + word.length + 1 > width
            result << word
          else
            result[-1] += " #{word}"
          end
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

    def run!(*command, **options)
      MediaCommand.run!(*command, **options)
    end
  end
end
