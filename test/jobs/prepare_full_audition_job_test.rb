require "test_helper"

class PrepareFullAuditionJobTest < ActiveJob::TestCase
  setup do
    @order = orders(:b2b_preview_ready)
    Campaign.create!(order: @order, business_name: "Bella Napoli", offer: "Pizza em dobro",
      contact: "@bella", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @asset.update!(duration_ms: 95_500)
    @asset.audio.attach(io: StringIO.new("private original"), filename: "original.mp3", content_type: "audio/mpeg")
  end

  test "attaches a marked full-length audition bound to the original recording" do
    calls = []
    render = ->(**kwargs) { calls << kwargs; File.binwrite(kwargs[:destination], "marked full") }
    Campaigns::AudioAudition.stub(:render, render) do
      assert_difference -> { GenerationCost.where(operation: "full_audition").count }, 1 do
        PrepareFullAuditionJob.perform_now(@asset.id)
      end
    end
    assert_equal 1, calls.size
    assert_equal 0, calls.first[:start_seconds]
    assert_equal @asset.track_duration_seconds, calls.first[:duration_seconds]
    @asset.reload
    assert @asset.full_audition_audio.attached?
    assert_equal "marked full", @asset.full_audition_audio.download
    metadata = @asset.full_audition_audio.blob.metadata
    assert_equal @asset.audio.blob.id, metadata["source_blob_id"]
    assert_equal Campaigns::AudioAudition::VERSION, metadata["watermark_version"]
    assert metadata["private_order_audio"]
    assert @asset.full_audition_ready?
  end

  test "second run is a no-op once the marked full audition is ready" do
    Campaigns::AudioAudition.stub(:render, ->(**kwargs) { File.binwrite(kwargs[:destination], "marked full") }) do
      PrepareFullAuditionJob.perform_now(@asset.id)
    end
    Campaigns::AudioAudition.stub(:render, ->(**_) { flunk "must not render twice" }) do
      assert_no_difference("ActiveStorage::Blob.count") { PrepareFullAuditionJob.perform_now(@asset.id) }
    end
  end

  test "archiving the recording enqueues the full audition" do
    assert_enqueued_with(job: PrepareFullAuditionJob, args: [ @asset.id ]) do
      ArchiveCampaignAudioJob.perform_now(@asset.id)
    end
    @asset.audio.purge
    Campaigns::AudioDownload.stub(:call, ->(_url, destination) { File.binwrite(destination, "fake MP3") }) do
      assert_enqueued_with(job: PrepareFullAuditionJob, args: [ @asset.id ]) do
        ArchiveCampaignAudioJob.perform_now(@asset.id)
      end
    end
  end
end
