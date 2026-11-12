require "test_helper"
require "open3"
require "tmpdir"

class Campaigns::VideoRendererTest < ActiveSupport::TestCase
  test "logos keep their proportions and transparency in the poster and real video and can replace the name" do
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: "Landel", offer: "Casa com 03 quartos\nR$ 750.000", show_cta: false)
    renderer = Campaigns::VideoRenderer.new(campaign)
    Dir.mktmpdir do |dir|
      source = File.join(dir, "logo.png")
      renderer.send(:run!, renderer.send(:image_command), "-size", "200x100", "xc:none", "-fill", "red", "-draw", "rectangle 20,20 180,80", source)
      File.open(source) { |file| campaign.logo.attach(io: file, filename: "logo.png", content_type: "image/png") }
      photo = File.join(dir, "photo.png")
      renderer.send(:run!, renderer.send(:image_command), "-size", "100x180", "xc:blue", photo)
      File.open(photo) { |file| campaign.photos.attach(io: file, filename: "photo.png", content_type: "image/png") }
      visuals = renderer.send(:make_visuals, dir)
      assert_equal [ "Landel" ], Nokogiri::XML(File.read(File.join(dir, "header.svg"))).css("text").map(&:text)
      dimensions = renderer.send(:run!, renderer.send(:image_command), File.join(dir, "business-logo.png"), "-format", "%w %h", "info:")
      assert_equal "260 130", dimensions
      alpha = renderer.send(:run!, renderer.send(:image_command), File.join(dir, "business-logo.png"), "-crop", "1x1+0+0", "-format", "%[fx:a]", "info:")
      assert_equal 0, alpha.to_f
      pixel = renderer.send(:run!, renderer.send(:image_command), visuals.fetch(:poster), "-crop", "1x1+150+140", "-format", "%[fx:r],%[fx:g],%[fx:b]", "info:")
      assert_equal [ 1, 0, 0 ], pixel.split(",").map(&:to_f)
      audio = File.join(dir, "audio.wav")
      renderer.send(:run!, "ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", audio)
      renderer.stub(:download_audio, ->(destination) { FileUtils.cp(audio, destination) }) { renderer.call }
      campaign.video.blob.open do |video|
        pixels = renderer.send(:run!, "ffmpeg", "-v", "error", "-ss", "1", "-i", video.path, "-vf", "crop=2:2:150:140,format=rgb24", "-frames:v", "1", "-f", "rawvideo", "-").bytes.first(3)
        [ 255, 0, 0 ].zip(pixels).each { |expected, actual| assert_in_delta expected, actual, 6 }
        metadata = JSON.parse(renderer.send(:run!, "ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height", "-of", "json", video.path))
        assert metadata.fetch("streams").any? { |stream| stream["codec_name"] == "h264" && stream["width"] == 720 && stream["height"] == 1280 }
        assert metadata.fetch("streams").any? { |stream| stream["codec_name"] == "aac" }
      end
      campaign.update!(business_name: "")
      renderer.send(:make_visuals, dir)
      assert_empty Nokogiri::XML(File.read(File.join(dir, "header.svg"))).css("text")
      campaign.update!(remove_logo: "1")
      no_brand = renderer.send(:make_visuals, dir)
      assert_empty Nokogiri::XML(File.read(File.join(dir, "header.svg"))).css("text,rect"), "Omitting a name and logo must not burn a placeholder into the video"
      pixel = renderer.send(:run!, renderer.send(:image_command), no_brand.fetch(:poster), "-crop", "1x1+150+140", "-format", "%[fx:r],%[fx:g],%[fx:b]", "info:").split(",").map(&:to_f)
      assert_operator pixel[0], :<, 0.05
      assert_operator pixel[2], :>, pixel[0] * 4
    end
  end

  test "a disguised SVG logo cannot select an image decoder" do
    campaign = Campaign.create!(order: orders(:b2b_approved), offer: "Oferta", show_cta: false)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>'),
      filename: "logo.png", content_type: "image/png", identify: false)
    campaign.logo.attach(blob)
    Dir.mktmpdir do |dir|
      assert_raises(RuntimeError) { Campaigns::VideoRenderer.new(campaign).send(:make_visuals, dir) }
    end
  end

  test "text wrapping respects authored lines blank lines and unbroken currency amounts" do
    renderer = Campaigns::VideoRenderer.new(nil)
    assert_equal [ "Casa com 03", "quartos", "R$\u00a0750.000" ], renderer.send(:wrap, "Casa com 03 quartos\r\nR$ 750.000", 12)
    assert_equal [ "Oferta", "", "Só hoje" ], renderer.send(:wrap, "Oferta\n\nSó hoje", 34)
    assert_equal [ "Por apenas", "R$\u00a0750.000" ], renderer.send(:wrap, "Por apenas R$ 750.000", 15)
    assert_equal [ "R$\u00a0750.000" ], renderer.send(:wrap, "R$ 750.000", 5)
    assert_equal [ "R$", "750.000" ], renderer.send(:wrap, "R$\n750.000", 34)
    text = Nokogiri::XML.fragment(renderer.send(:text_lines, "Oferta & <casa>" + "\n" * 170,
      width: 34, x: 60, y: 96, size: 30, color: "#ffffff", available_height: 208))
    assert_equal 171, text.css("text").size
    assert_equal "Oferta & <casa>", text.at_css("text").text
    assert text.css("text").all? { |line| line["font-size"].to_f.positive? }
    assert_operator text.css("text").last["y"].to_f, :<, 304
  end

  test "poster and video use the selected CTA color and omit the entire strip when disabled" do
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: "Landel", offer: "Casa com 03 quartos\nR$ 750.000",
      contact: "@landel", call_to_action: "Saiba mais no Instagram", style: "animado", cta_color: "#6b21a8")
    Dir.mktmpdir do |dir|
      renderer = Campaigns::VideoRenderer.new(campaign)
      photo = File.join(dir, "photo.png")
      renderer.send(:run!, renderer.send(:image_command), "-size", "100x180", "xc:#00ff00", photo)
      File.open(photo) { |file| campaign.photos.attach(io: file, filename: "photo.png", content_type: "image/png") }
      audio = File.join(dir, "audio.wav")
      renderer.send(:run!, "ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", audio)
      [ true, false ].each do |enabled|
        campaign.update!(show_cta: enabled)
        visuals = renderer.send(:make_visuals, dir)
        offer = Nokogiri::XML(File.read(File.join(dir, "offer.svg")))
        assert_equal [ "APROVEITE A OFERTA", "Casa com 03 quartos", "R$\u00a0750.000" ], offer.css("text").map(&:text)
        assert_equal enabled, visuals[:cta].present?
        height = offer.at_css("svg")["height"].to_i
        assert_operator height, :<, 200, "A two-line offer must not leave a tall empty panel"
        assert_equal enabled ? visuals[:cta_y] - 12 : 1244, visuals[:offer_y] + height
        assert_equal 1114, visuals[:cta_y] if enabled
        renderer.stub(:download_audio, ->(destination) { FileUtils.cp(audio, destination) }) { renderer.call }
        campaign.poster.blob.open do |poster|
          pixel = renderer.send(:run!, renderer.send(:image_command), poster.path, "-crop", "1x1+650+1205", "-format", "%[fx:r],%[fx:g],%[fx:b]", "info:").split(",").map(&:to_f)
          expected = enabled ? [ 107, 33, 168 ] : [ 15, 37, 14 ]
          expected.zip(pixel).each { |value, actual| assert_in_delta value / 255.0, actual, 0.01 }
        end
        campaign.video.blob.open do |video|
          pixels = renderer.send(:run!, "ffmpeg", "-v", "error", "-ss", "2.8", "-i", video.path, "-vf", "crop=2:2:650:1206,format=rgb24", "-frames:v", "1", "-f", "rawvideo", "-").bytes.first(3)
          expected = enabled ? [ 107, 33, 168 ] : [ 15, 37, 14 ]
          expected.zip(pixels).each { |value, actual| assert_in_delta value, actual, 6 }
          metadata = JSON.parse(renderer.send(:run!, "ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_name", "-of", "json", video.path))
          assert_in_delta 3, metadata.fetch("format").fetch("duration").to_f, 0.1
          assert metadata.fetch("streams").any? { |stream| stream["codec_name"] == "aac" }, "Removing a visual input must not change the audio stream mapping"
        end
      end
    end
  end

  test "offer panels grow with wrapped and authored lines while keeping their bottom anchored" do
    campaign = Campaign.create!(order: orders(:b2b_approved), offer: "Oferta", show_cta: false)
    renderer = Campaigns::VideoRenderer.new(campaign)
    Dir.mktmpdir do |dir|
      heights = [ "Oferta", "Casa 3 quartos\nR$ 300 mil", "Uma casa com muito espaço para toda a família, com jardim e garagem", "Oferta\n\nSó hoje", ("Oferta\n" * 25).strip ].map do |text|
        campaign.offer = text
        visuals = renderer.send(:make_visuals, dir)
        svg = Nokogiri::XML(File.read(File.join(dir, "offer.svg")))
        height = svg.at_css("svg")["height"].to_i
        last_line = svg.css("text").last
        assert_equal height, svg.at_css("rect")["height"].to_i
        assert_equal 1244, visuals[:offer_y] + height
        assert_in_delta 24, height - last_line["y"].to_f - last_line["font-size"].to_f * 0.25, 1
        assert_operator height, :<=, 328, "Long text must stay within the bounded offer area"
        height
      end
      assert_operator heights[1], :>, heights[0]
      assert_operator heights[2], :>, heights[1]
      assert_equal heights[2], heights[3], "Blank authored lines must keep their spacing"
      assert_operator heights[4], :>, heights[3]
    end
  end

  test "uploaded photos cannot select an SVG decoder by disguising their content type" do
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: "Loja", offer: "Oferta", contact: "@loja", call_to_action: "Peça", style: "animado")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="red"/></svg>'),
      filename: "photo.png", content_type: "image/png", identify: false)
    campaign.photos.attach(blob)
    Dir.mktmpdir do |dir|
      assert_raises(RuntimeError) { Campaigns::VideoRenderer.new(campaign).send(:make_visuals, dir) }
    end
  end

  test "supported JPEG and WebP photos keep rendering with their explicit decoder" do
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: "Loja", offer: "Oferta", contact: "@loja", call_to_action: "Peça", style: "animado")
    Dir.mktmpdir do |dir|
      renderer = Campaigns::VideoRenderer.new(campaign)
      %w[jpeg webp].each do |format|
        photo = File.join(dir, "photo.#{format}")
        renderer.send(:run!, renderer.send(:image_command), "-size", "30x50", "xc:red", photo)
        File.open(photo) { |file| campaign.photos.attach(io: file, filename: "photo.#{format}", content_type: "image/#{format}") }
      end
      visuals = renderer.send(:make_visuals, dir)
      assert_equal 2, visuals.fetch(:backgrounds).size
      assert File.exist?(visuals.fetch(:poster))
    end
  end

  test "recovers a missing archived audio file from its provider without regenerating music" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Teste", offer: "Oferta", contact: "@teste", call_to_action: "Peça", style: "animado")
    asset = order.order_assets.find_by!(kind: "music_variant", variant_index: 0)
    asset.audio.attach(io: StringIO.new("missing audio"), filename: "missing.mp3", content_type: "audio/mpeg")
    asset.audio.blob.service.delete(asset.audio.blob.key)
    order.update!(status: "approved", approved_variant: "a", approved_music_generation_id: asset.music_generation_id)
    Dir.mktmpdir do |dir|
      destination = File.join(dir, "recovered.mp3")
      Campaigns::AudioDownload.stub(:call, ->(_url, path) { File.binwrite(path, "recovered audio") }) do
        assert_enqueued_with(job: ArchiveCampaignAudioJob, args: [ asset.id ]) do
          Campaigns::VideoRenderer.new(campaign).send(:download_audio, destination)
        end
      end
      assert_equal "recovered audio", File.binread(destination)
    end
  end

  test "five photos follow the saved order and crossfade without interrupting audio" do
    skip "FFmpeg is required" unless system("ffmpeg", "-version", out: File::NULL, err: File::NULL)
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: "Loja", offer: "Oferta da semana", contact: "@loja", call_to_action: "Saiba mais no Instagram", style: "animado")
    Dir.mktmpdir do |dir|
      renderer = Campaigns::VideoRenderer.new(campaign)
      colors = %w[red lime blue yellow magenta]
      files = colors.each_with_index.map do |color, index|
        path = File.join(dir, "#{index}.png")
        _, errors, status = Open3.capture3(renderer.send(:image_command), "-size", "100x180", "xc:#{color}", path)
        assert status.success?, errors
        { io: File.open(path), filename: "#{index}.png", content_type: "image/png" }
      end
      campaign.photos.attach(files)
      files.each { |file| file[:io].close }
      ids = campaign.product_photos.map(&:id)
      campaign.update!(photo_order: [ ids[1], ids[0], *ids.drop(2) ])
      audio = File.join(dir, "audio.wav")
      _, errors, status = Open3.capture3("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=6", audio)
      assert status.success?, errors
      renderer.stub(:download_audio, ->(destination) { FileUtils.cp(audio, destination) }) { renderer.call }
      campaign.video.blob.open do |video|
        samples = [ 0.4, 1.9, 2.9, 4.1, 5.5, 1.375 ].map do |time|
          pixels, errors, status = Open3.capture3("ffmpeg", "-v", "error", "-ss", time.to_s, "-i", video.path, "-vf", "crop=2:2:360:500,format=rgb24", "-frames:v", "1", "-f", "rawvideo", "-")
          assert status.success?, errors
          pixels.bytes.first(3)
        end
        assert samples[0][1] > 200 && samples[0][0] < 30, "The chosen opener must be green, despite being uploaded second"
        assert samples[1][0] > 200 && samples[1][1] < 30, "Second photo must now be red"
        assert samples[2][2] > 200 && samples[2][0] < 30, "Third photo must be blue"
        assert samples[3][0] > 200 && samples[3][1] > 200, "Fourth photo must be yellow"
        assert samples[4][0] > 200 && samples[4][2] > 200, "Fifth photo must be magenta"
        assert samples[5][0].between?(60, 195) && samples[5][1].between?(60, 195), "Transition must blend red and green rather than cut to black"
        metadata, = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "format=duration:stream=codec_name", "-of", "json", video.path)
        info = JSON.parse(metadata)
        assert_in_delta 6, info.fetch("format").fetch("duration").to_f, 0.1
        assert info.fetch("streams").any? { |stream| stream["codec_name"] == "aac" }
      end
    end
  end

  test "renders uploaded photo with motion and escaped offer into a playable vertical MP4" do
    tools = %w[ffmpeg ffprobe].all? { |tool| ENV.fetch("PATH").split(":").any? { |path| File.executable?(File.join(path, tool)) } }
    skip "FFmpeg is required for the rendering smoke test" unless tools
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: "Café & Pão <Aurora>", offer: "Café + pão por R$ 12. Só de segunda a sexta.", contact: "@cafe.exemplo", call_to_action: "Venha nos visitar", style: "acolhedor")
    Dir.mktmpdir do |dir|
      audio = File.join(dir, "audio.wav")
      _, errors, status = Open3.capture3("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", audio)
      assert status.success?, errors
      renderer = Campaigns::VideoRenderer.new(campaign)
      photo = File.join(dir, "photo.png")
      _, errors, status = Open3.capture3(renderer.send(:image_command), "-size", "100x100", "xc:#c1f66b", "-fill", "#365320", "-draw", "rectangle 0,0 20,100", photo)
      assert status.success?, errors
      renderer.stub(:download_audio, ->(destination) { FileUtils.cp(audio, destination) }) { renderer.call }
      assert campaign.video.attached?, "Merchants without a photo must still receive a video"
      campaign.photo.attach(io: File.open(photo), filename: "photo.png", content_type: "image/png")
      renderer.stub(:download_audio, ->(destination) { FileUtils.cp(audio, destination) }) { renderer.call }
      assert campaign.video.attached?
      campaign.poster.blob.open do |poster|
        pixel, = Open3.capture3(renderer.send(:image_command), poster.path, "-crop", "1x1+360+500", "-format", "%[fx:r],%[fx:g],%[fx:b]", "info:")
        red, green, blue = pixel.split(",").map(&:to_f)
        assert green > 0.6 && green > red && red > blue, "The uploaded green photo must remain visible beneath the shading"
      end
      campaign.video.blob.open do |video|
        output, errors, status = Open3.capture3("ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height", "-of", "json", video.path)
        assert status.success?, errors
        streams = JSON.parse(output).fetch("streams")
        assert streams.any? { |stream| stream["codec_name"] == "h264" && stream["width"] == 720 && stream["height"] == 1280 }
        assert streams.any? { |stream| stream["codec_name"] == "aac" }
        hashes, errors, status = Open3.capture3("ffmpeg", "-v", "error", "-i", video.path, "-vf", "fps=2,crop=600:400:60:280", "-an", "-f", "framemd5", "-")
        assert status.success?, errors
        frames = hashes.lines.reject { |line| line.start_with?("#") }.map { |line| line.split(",").last.strip }
        assert_operator frames.uniq.size, :>, 1, "The product area must move even without text overlays"
      end
    end
  end
end
