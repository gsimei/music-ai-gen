require "test_helper"

class SoundtrackJobsSecurityTest < ActiveSupport::TestCase
  setup do
    @order = orders(:b2b_paid)
    @order.music_generations.destroy_all
    @input = @order.soundtrack_input
    @input.file.attach(io: StringIO.new("video bytes"), filename: "test.mp4", content_type: "video/mp4")
  end

  test "worker rejects existing oversized blobs without downloading or contacting provider" do
    @input.file.blob.update_columns(byte_size: SoundtrackInput::MAX_FILE_SIZE + 1)
    ActiveStorage::Blob.service.stub(:download, ->(*) { flunk "oversized blob downloaded" }) do
      MusicGenerator::MurekaFilesUploadClient.stub(:call, ->(**) { flunk "provider called" }) do
        UploadSoundtrackInputToMurekaJob.perform_now(@order.id, @input.id)
      end
    end
    assert_equal "failed", @input.reload.mureka_file_status
    assert_no_enqueued_jobs only: GenerateSoundtrackJob
  end

  test "upload job ignores unpaid orders and obsolete input IDs" do
    MusicGenerator::MurekaFilesUploadClient.stub(:call, ->(**) { flunk "provider called" }) do
      UploadSoundtrackInputToMurekaJob.perform_now(@order.id, @input.id + 1)
      @order.update!(status: "pending")
      UploadSoundtrackInputToMurekaJob.perform_now(@order.id, @input.id)
    end
    assert_equal "pending", @input.reload.mureka_file_status
  end

  test "upload streams a valid attachment and duplicate delivery submits only once" do
    calls = 0
    MusicGenerator::MurekaFilesUploadClient.stub(:call, ->(file_path:, **) {
      calls += 1
      assert_equal "video bytes", File.binread(file_path)
      assert_equal ".mp4", File.extname(file_path)
      ServiceResult.new(success: true, value: { file_id: "uploaded" }, errors: nil)
    }) do
      2.times { UploadSoundtrackInputToMurekaJob.perform_now(@order.id, @input.id) }
    end
    assert_equal 1, calls
    assert @input.reload.ready?
    assert_enqueued_with(job: GenerateSoundtrackJob, args: [ @order.id, @input.id ])
  end

  test "generation rejects campaigns at job and generic service boundaries" do
    @order.create_campaign!(offer: "Oferta", style: "animado", show_cta: false)
    @input.update!(mureka_file_status: "ready", mureka_file_id: "uploaded")
    MusicGenerator::MurekaSoundtrackClient.stub(:call, ->(**) { flunk "provider called" }) do
      GenerateSoundtrackJob.perform_now(@order.id)
      assert @order.reload.paid?
      @order.update!(status: "music_generating")
      assert MusicGenerator::Generator.call(order: @order).failure?
    end
  end

  test "initial soundtrack and generic job replays share a persisted generation claim" do
    @input.update!(mureka_file_status: "ready", mureka_file_id: "uploaded")
    calls = 0
    MusicGenerator::MurekaSoundtrackClient.stub(:call, ->(**) {
      calls += 1
      assert @order.music_generations.pending.exists?, "claim must precede provider call"
      ServiceResult.new(success: true, value: { job_id: "generated" }, errors: nil)
    }) do
      2.times { GenerateSoundtrackJob.perform_now(@order.id, @input.id) }
      GenerateMusicJob.perform_now(@order.id)
    end
    assert_equal 1, calls
    assert @order.reload.music_generating?
    assert_equal "generated", @order.music_generations.last.mureka_job_id
  end

  test "legitimate soundtrack regeneration can reserve a new iteration after completion" do
    @input.update!(mureka_file_status: "ready", mureka_file_id: "uploaded")
    MusicGenerator::MurekaSoundtrackClient.stub(:call, ->(**) { ServiceResult.new(success: true, value: { job_id: "generated" }, errors: nil) }) do
      GenerateSoundtrackJob.perform_now(@order.id, @input.id)
      @order.music_generations.reload.last.update!(status: "completed")
      @order.reload.update!(status: "preview_ready")
      assert Orders::MusicRegenerator.call(order: @order).success?
      GenerateMusicJob.perform_now(@order.id)
    end
    assert_equal [ 1, 2 ], @order.music_generations.order(:iteration).pluck(:iteration)
    assert_equal 1, @order.reload.music_regen_used
  end

  test "failed provider attempt remains claimed against stale job replays" do
    @input.update!(mureka_file_status: "ready", mureka_file_id: "uploaded")
    @order.update!(status: "music_generating")
    calls = 0
    MusicGenerator::MurekaSoundtrackClient.stub(:call, ->(**) {
      calls += 1
      ServiceResult.new(success: false, value: nil, errors: :timeout)
    }) do
      assert MusicGenerator::Generator.call(order: @order).failure?
      assert_equal :busy, MusicGenerator::Generator.call(order: @order).errors
    end
    assert_equal 1, calls
  end

  test "another worker owning the generation does not mark the order failed" do
    @input.update!(mureka_file_status: "ready", mureka_file_id: "uploaded")
    MusicGenerator::Generator.stub(:call, ->(**) { ServiceResult.new(success: false, value: nil, errors: :busy) }) do
      GenerateSoundtrackJob.perform_now(@order.id, @input.id)
    end
    assert @order.reload.music_generating?
  end

  test "retry can resume after state transition if no provider claim was created" do
    @input.update!(mureka_file_status: "ready", mureka_file_id: "uploaded")
    MusicGenerator::Generator.stub(:call, ->(**) { raise "interrupted before claim" }) do
      assert_raises(RuntimeError) { GenerateSoundtrackJob.perform_now(@order.id, @input.id) }
    end
    assert @order.reload.music_generating?
    assert_empty @order.music_generations.reload
    calls = 0
    MusicGenerator::MurekaSoundtrackClient.stub(:call, ->(**) {
      calls += 1
      ServiceResult.new(success: true, value: { job_id: "resumed" }, errors: nil)
    }) do
      2.times { GenerateSoundtrackJob.perform_now(@order.id, @input.id) }
    end
    assert_equal 1, calls
    assert_equal "resumed", @order.music_generations.reload.last.mureka_job_id
  end
end
