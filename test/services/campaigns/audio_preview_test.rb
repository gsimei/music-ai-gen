require "test_helper"
require "tmpdir"

class Campaigns::AudioPreviewTest < ActiveSupport::TestCase
  setup do
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
  end

  test "long tracks produce a thirty second excerpt with a saved start and fade" do
    Dir.mktmpdir do |dir|
      source = tone(dir, 40)
      destination = File.join(dir, "preview.m4a")
      sync = { "sections" => [ { "section_type" => "chorus", "lines" => [ { "start" => 6000, "end" => 25000 } ] } ] }
      metadata = Campaigns::AudioPreview.render(source: source, destination: destination, lyrics_sync: sync)
      assert_in_delta 5.75, metadata.fetch("start_seconds"), 0.001
      assert_equal 30, metadata.fetch("duration_seconds")
      assert_in_delta 30, duration(destination), 0.05
      pcm = Campaigns::MediaCommand.run!("ffmpeg", "-v", "error", "-i", destination, "-f", "f32le", "-ac", "1", "-ar", "8000", "-").unpack("e*")
      assert_operator pcm.first(800).sum(&:abs) / 800, :>, 0.01
      assert_operator pcm.last(400).sum(&:abs) / 400, :<, 0.01
    end
  end

  test "chosen lengths and the full recording produce real audio with the requested duration" do
    Dir.mktmpdir do |dir|
      source = tone(dir, 120.25)
      [ [ 60, 10 ], [ 90, 30.25 ], [ 72.75, 2.5 ], [ nil, nil ] ].each_with_index do |(length, start), index|
        destination = File.join(dir, "length-#{index}.m4a")
        metadata = Campaigns::AudioPreview.render(source: source, destination: destination, lyrics_sync: nil,
          duration_seconds: length, start_seconds: start)
        expected = length || 120.25
        assert_in_delta expected, metadata.fetch("duration_seconds"), 0.001
        assert_in_delta expected, duration(destination), 0.05
        assert_in_delta start || 0, metadata.fetch("start_seconds"), 0.001
      end
      [ 0, -1, "NaN", "Infinity", "bad" ].each do |invalid|
        assert_raises(ArgumentError) do
          Campaigns::AudioPreview.render(source: source, destination: File.join(dir, "invalid.m4a"), lyrics_sync: nil, duration_seconds: invalid)
        end
      end
      assert_raises(ArgumentError) do
        Campaigns::AudioPreview.render(source: source, destination: File.join(dir, "past-end.m4a"), lyrics_sync: nil, duration_seconds: 90, start_seconds: 30.26)
      end
    end
  end

  test "a full length video with thirty photos spreads scenes across the song and preserves approved audio packets" do
    Dir.mktmpdir do |dir|
      File.open(tone(dir, 180.25)) { |file| @asset.audio.attach(io: file, filename: "full-song.wav", content_type: "audio/wav") }
      @asset.update!(excerpt_duration_seconds: nil)
      PrepareCampaignAudioJob.perform_now(@asset.id)
      assert @asset.reload.audition_ready?
      assert_in_delta 180.25, @asset.campaign_audio.blob.metadata.fetch("duration_seconds"), 0.001
      renderer = Campaigns::VideoRenderer.new(@campaign)
      Array.new(30) { |index| %w[red lime blue][index % 3] }.each_with_index do |color, index|
        path = File.join(dir, "photo-#{index}.png")
        Campaigns::MediaCommand.run!(renderer.send(:image_command), "-size", "100x180", "xc:#{color}", path)
        File.open(path) { |file| @campaign.photos.attach(io: file, filename: "photo-#{index}.png", content_type: "image/png") }
      end
      assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id).success?
      renderer.call
      @asset.campaign_audio.blob.open do |preview|
        @campaign.video.blob.open do |video|
          assert_equal packet_hashes(preview.path), packet_hashes(video.path)
          assert_in_delta 180.25, duration(video.path), 0.05
          [ [ 3, 0 ], [ 99, 1 ], [ 177, 2 ] ].each do |time, color_channel|
            pixel = Campaigns::MediaCommand.run!("ffmpeg", "-v", "error", "-ss", time.to_s, "-i", video.path,
              "-vf", "crop=2:2:360:500,format=rgb24", "-frames:v", "1", "-f", "rawvideo", "-").bytes.first(3)
            assert_operator pixel.fetch(color_channel), :>, 200, "Photo must still fill its scene at #{time} seconds"
          end
        end
      end
      assert_in_delta 180.25, @campaign.video.blob.metadata.fetch("duration_seconds"), 0.001
      assert_equal 1, @order.completed_music_rounds
    end
  end

  test "archiving prepares a short excerpt once and final video preserves every audio packet" do
    Dir.mktmpdir do |dir|
      source = tone(dir, 2)
      Campaigns::AudioDownload.stub(:call, ->(_url, destination) { FileUtils.cp(source, destination) }) do
        assert_enqueued_with(job: PrepareCampaignAudioJob, args: [ @asset.id ]) { ArchiveCampaignAudioJob.perform_now(@asset.id) }
      end
      version_before = @order.creation_version
      PrepareCampaignAudioJob.perform_now(@asset.id)
      assert @asset.reload.campaign_preview_ready?
      assert @asset.audition_ready?
      refute_equal @asset.campaign_audio.blob.checksum, @asset.audition_audio.blob.checksum
      assert_not_equal version_before, @order.reload.creation_version
      assert_in_delta 2, @asset.campaign_audio.blob.metadata.fetch("duration_seconds"), 0.05
      event = @order.generation_costs.find_by!(operation: "audio_preview")
      assert_equal "local", event.provider
      assert_operator event.usage.fetch("wall_seconds"), :>, 0
      assert_nil event.estimated_brl
      assert_no_difference([ "ActiveStorage::Blob.count", "GenerationCost.count" ]) { PrepareCampaignAudioJob.perform_now(@asset.id) }
      assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id).success?
      Campaigns::VideoRenderer.new(@campaign).call
      @asset.campaign_audio.blob.open do |preview|
        @campaign.video.blob.open do |video|
          assert_equal packet_hashes(preview.path), packet_hashes(video.path), "Video must copy the approved audio, without a second cut, encode or fade"
          assert_in_delta duration(preview.path), duration(video.path), 0.05
        end
      end
    end
  end

  test "invalid source leaves originals intact and can be retried without another generation" do
    @asset.audio.attach(io: StringIO.new("invalid mp3"), filename: "original.mp3", content_type: "audio/mpeg")
    before = @order.completed_music_rounds
    PrepareCampaignAudioJob.perform_now(@asset.id)
    assert_equal "failed", @asset.reload.campaign_preview_status
    refute @asset.campaign_audio.attached?
    assert @asset.audio.attached?
    assert_equal before, @order.completed_music_rounds
    assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id).failure?
    Dir.mktmpdir do |dir|
      File.open(tone(dir, 1)) { |file| @asset.audio.attach(io: file, filename: "recovered.wav", content_type: "audio/wav") }
      PrepareCampaignAudioJob.perform_now(@asset.id)
      assert @asset.reload.campaign_preview_ready?
      assert_equal before, @order.completed_music_rounds
    end
  end

  test "manual excerpt is rendered from the chosen offset and its packets survive video assembly" do
    Dir.mktmpdir do |dir|
      source = tone(dir, 32)
      File.open(source) { |file| @asset.audio.attach(io: file, filename: "original.wav", content_type: "audio/wav") }
      PrepareCampaignAudioJob.perform_now(@asset.id)
      old_blob = @asset.reload.campaign_audio.blob.id
      result = Campaigns::ExcerptSettings.call(order: @order, asset_id: @asset.id, start_seconds: 1.25, revision: 0)
      assert result.success?
      PrepareCampaignAudioJob.perform_now(@asset.id, 1)
      assert @asset.reload.campaign_preview_ready?
      assert_not_equal old_blob, @asset.campaign_audio.blob.id
      assert_in_delta 1.25, @asset.campaign_audio.blob.metadata.fetch("start_seconds"), 0.001
      assert_equal 1, @asset.campaign_audio.blob.metadata.fetch("preview_revision")
      assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id, preview_revision: 1).success?
      Campaigns::VideoRenderer.new(@campaign).call
      @asset.campaign_audio.blob.open do |preview|
        @campaign.video.blob.open do |video|
          assert_equal packet_hashes(preview.path), packet_hashes(video.path)
          assert_in_delta 30, duration(video.path), 0.05
        end
      end
      assert_equal 1, @order.completed_music_rounds
    end
  end

  test "failed recut preserves both the full recording and last successful excerpt" do
    Dir.mktmpdir do |dir|
      File.open(tone(dir, 32)) { |file| @asset.audio.attach(io: file, filename: "original.wav", content_type: "audio/wav") }
      PrepareCampaignAudioJob.perform_now(@asset.id)
      original_blob = @asset.audio.blob.id
      preview_blob = @asset.reload.campaign_audio.blob.id
      assert Campaigns::ExcerptSettings.call(order: @order, asset_id: @asset.id, start_seconds: 1, revision: 0).success?
      Campaigns::AudioPreview.stub(:render, ->(**_) { raise "temporary disk error" }) { PrepareCampaignAudioJob.perform_now(@asset.id, 1) }
      assert_equal "failed", @asset.reload.campaign_preview_status
      assert_equal original_blob, @asset.audio.blob.id
      assert_equal preview_blob, @asset.campaign_audio.blob.id
      PrepareCampaignAudioJob.perform_now(@asset.id, 1)
      assert @asset.reload.campaign_preview_ready?
    end
  end

  test "audition contains speech and moving the excerpt does not move the watermark on the source timeline" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "silence.wav")
      Campaigns::MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono", "-t", "12", source)
      decoded = [ 0, 2 ].map do |start|
        destination = File.join(dir, "marked-#{start}.m4a")
        Campaigns::AudioAudition.render(source: source, destination: destination, start_seconds: start, duration_seconds: 12)
        assert_in_delta 12, duration(destination), 0.05
        Campaigns::MediaCommand.run!("ffmpeg", "-v", "error", "-i", destination, "-f", "f32le", "-ac", "1", "-ar", "8000", "-").unpack("e*")
      end
      energy = ->(samples, start, length) { samples.slice(start * 8000, length * 8000).sum(&:abs) / (length * 8000) }
      assert_operator energy.call(decoded[0], 0, 2), :>, 0.01, "Watermark asset must contain actual audible speech"
      assert_operator energy.call(decoded[0], 4, 2), :<, 0.001
      assert_operator energy.call(decoded[1], 6, 2), :>, 0.01
      first = decoded[0].slice(8 * 8000, 2 * 8000)
      shifted = decoded[1].slice(6 * 8000, 2 * 8000)
      error = first.zip(shifted).sum { |a, b| (a - b).abs } / first.size
      assert_operator error, :<, 0.015, "The same source interval must carry the same watermark after a recut (allowing AAC frame differences)"
    end
  end

  test "existing approved campaigns can gain protected auditions without changing the final excerpt" do
    Dir.mktmpdir do |dir|
      File.open(tone(dir, 2)) { |file| @asset.audio.attach(io: file, filename: "original.wav", content_type: "audio/wav") }
      PrepareCampaignAudioJob.perform_now(@asset.id)
      clean_blob = @asset.reload.campaign_audio.blob.id
      assert Orders::MusicApprover.call(order: @order, asset_id: @asset.id).success?
      @asset.audition_audio.purge
      PrepareCampaignAudioJob.perform_now(@asset.id)
      assert @asset.reload.audition_ready?
      assert_equal clean_blob, @asset.campaign_audio.blob.id
    end
  end

  test "an unchosen version can finish preparation after its sibling has been approved" do
    Dir.mktmpdir do |dir|
      File.open(tone(dir, 2)) { |file| @asset.audio.attach(io: file, filename: "original.wav", content_type: "audio/wav") }
      @order.update!(status: "approved", approved_variant: "b", approved_music_generation_id: @asset.music_generation_id)
      PrepareCampaignAudioJob.perform_now(@asset.id)
      assert @asset.reload.audition_ready?
      assert_nil @asset.playback_url
      assert_equal "b", @order.reload.approved_variant
    end
  end

  private

  def tone(dir, seconds)
    path = File.join(dir, "tone.wav")
    Campaigns::MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=#{seconds}", path)
    path
  end

  def duration(path)
    Float(Campaigns::MediaCommand.run!("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", path))
  end

  def packet_hashes(path)
    data = Campaigns::MediaCommand.run!("ffprobe", "-v", "error", "-select_streams", "a:0", "-show_packets", "-show_data_hash", "sha256", "-of", "json", path)
    JSON.parse(data).fetch("packets").map { |packet| packet.fetch("data_hash") }
  end
end
