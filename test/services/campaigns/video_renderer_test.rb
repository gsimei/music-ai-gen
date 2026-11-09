require "test_helper"
require "open3"
require "tmpdir"

class Campaigns::VideoRendererTest < ActiveSupport::TestCase
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
        assert_enqueued_with(job: ArchiveCampaignAudioJob, args: [asset.id]) do
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
      campaign.update!(photo_order: [ids[1], ids[0], *ids.drop(2)])
      audio = File.join(dir, "audio.wav")
      _, errors, status = Open3.capture3("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=6", audio)
      assert status.success?, errors
      renderer.stub(:download_audio, ->(destination) { FileUtils.cp(audio, destination) }) { renderer.call }
      campaign.video.blob.open do |video|
        samples = [0.4, 1.9, 2.9, 4.1, 5.5, 1.375].map do |time|
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
    campaign = Campaign.create!(order: orders(:b2b_approved), business_name: 'Café & Pão <Aurora>', offer: 'Café + pão por R$ 12. Só de segunda a sexta.', contact: '@cafe.exemplo', call_to_action: 'Venha nos visitar', style: 'acolhedor')
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
