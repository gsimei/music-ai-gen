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
      sync = { "sections" => [{ "section_type" => "chorus", "lines" => [{ "start" => 6000, "end" => 25000 }] }] }
      metadata = Campaigns::AudioPreview.render(source: source, destination: destination, lyrics_sync: sync)
      assert_in_delta 5.75, metadata.fetch("start_seconds"), 0.001
      assert_equal 30, metadata.fetch("duration_seconds")
      assert_in_delta 30, duration(destination), 0.05
      pcm = Campaigns::MediaCommand.run!("ffmpeg", "-v", "error", "-i", destination, "-f", "f32le", "-ac", "1", "-ar", "8000", "-").unpack("e*")
      assert_operator pcm.first(800).sum(&:abs) / 800, :>, 0.01
      assert_operator pcm.last(400).sum(&:abs) / 400, :<, 0.01
    end
  end

  test "archiving prepares a short excerpt once and final video preserves every audio packet" do
    Dir.mktmpdir do |dir|
      source = tone(dir, 2)
      Campaigns::AudioDownload.stub(:call, ->(_url, destination) { FileUtils.cp(source, destination) }) do
        assert_enqueued_with(job: PrepareCampaignAudioJob, args: [@asset.id]) { ArchiveCampaignAudioJob.perform_now(@asset.id) }
      end
      version_before = @order.creation_version
      PrepareCampaignAudioJob.perform_now(@asset.id)
      assert @asset.reload.campaign_preview_ready?
      assert_not_equal version_before, @order.reload.creation_version
      assert_in_delta 2, @asset.campaign_audio.blob.metadata.fetch("duration_seconds"), 0.05
      event = @order.generation_costs.find_by!(operation: "audio_preview")
      assert_equal "local", event.provider
      assert_operator event.usage.fetch("wall_seconds"), :>, 0
      assert_nil event.estimated_brl
      assert_no_difference(["ActiveStorage::Blob.count", "GenerationCost.count"]) { PrepareCampaignAudioJob.perform_now(@asset.id) }
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
