# frozen_string_literal: true

require "test_helper"

# Stub the MusicGenerator namespace so the file loads before implementation.
module MusicGenerator; end unless defined?(MusicGenerator)

# Tests for PollMurekaStatusJob
#
# Responsibilities:
# - Finds MusicGeneration by id; raises ActiveRecord::RecordNotFound if missing
# - Calls MurekaStatusClient.call(job_id: music_generation.mureka_job_id)
# - On status "pending":
#   - Increments music_generation.poll_count by 1
#   - If poll_count < MAX_POLLS (40): re-enqueues itself with wait: 15.seconds
#   - If poll_count >= MAX_POLLS: calls order.fail_music! (gives up)
# - On status "succeeded":
#   - Creates 2 OrderAsset records with kind "music_variant", variant_index 0/1,
#     provider_url, flac_url, wav_url, duration_ms from Mureka choices
#   - Calls order.music_ready!
#   - Updates music_generation.status to "completed"
# - On status "failed": calls order.fail_music!, updates music_generation.status to "failed"
# - On MurekaStatusClient failure: calls order.fail_music!, updates music_generation.status to "failed"
#
# Job interface:
#   PollMurekaStatusJob.perform_later(music_generation_id)
#
# Notes:
# - MusicGeneration needs new columns: mureka_job_id (string), poll_count (integer, default 0),
#   model (string). These are added as part of ROADMAP item 11 migration.
# - OrderAsset needs new kind "music_variant" and columns:
#   variant_index (integer), provider_url (string), flac_url (string), wav_url (string), duration_ms (integer).
# - Tests use helper methods to build MusicGeneration in the required state using
#   update_columns (bypasses validations) after loading from fixtures.
#
# PREREQUISITE FIXTURES (must be added before tests will pass):
#   test/fixtures/music_generations.yml — a "music_generation_polling" entry:
#     order: b2c_music_generating
#     mureka_job_id: "job_poll_test"
#     poll_count: 0
#     status: "pending"
#     provider: "mureka"
#     model: "auto"
#     voice: standard_voice
#     lyrics_draft: draft_lyrics_ready_v1   (or a new lyrics_approved draft)
#     iteration: 2
#     music_style: "pop"
#   AND a "music_generation_at_poll_limit" entry with poll_count: 40
class PollMurekaStatusJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper
  TWO_CHOICES = [
    {
      url:      "https://cdn.mureka.ai/song1.mp3",
      flac_url: "https://cdn.mureka.ai/song1.flac",
      wav_url:  "https://cdn.mureka.ai/song1.wav",
      duration_ms: 180_000
    },
    {
      url:      "https://cdn.mureka.ai/song2.mp3",
      flac_url: "https://cdn.mureka.ai/song2.flac",
      wav_url:  "https://cdn.mureka.ai/song2.wav",
      duration_ms: 192_000
    }
  ].freeze

  # Build a stub ServiceResult for MurekaStatusClient
  def status_result(status:, choices: nil)
    ServiceResult.new(
      success: true,
      value:   { status: status, choices: choices },
      errors:  nil
    )
  end

  def failure_result
    ServiceResult.new(success: false, value: nil, errors: :api_error)
  end

  # Helper: loads music_generation fixture and patches mureka-specific columns
  # that don't exist yet (they are part of the migration in ROADMAP 11)
  def music_generation_in_polling_state(poll_count: 0, mureka_job_id: "job_poll_test")
    mg = music_generations(:generation_pending)
    mg.update_columns(
      mureka_job_id: mureka_job_id,
      poll_count:    poll_count,
      status:        "pending"
    )
    mg
  end

  # ---------------------------------------------------------------------------
  # Status: pending — within poll limit
  # ---------------------------------------------------------------------------

  test "pending within limit: re-enqueues PollMurekaStatusJob with 15-second wait" do
    mg      = music_generation_in_polling_state(poll_count: 0)
    pending = status_result(status: "pending")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { pending }) do
      assert_enqueued_with(job: PollMurekaStatusJob, args: [mg.id]) do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  test "pending within limit: increments poll_count by 1" do
    mg      = music_generation_in_polling_state(poll_count: 5)
    pending = status_result(status: "pending")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { pending }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal 6, mg.reload.poll_count
  end

  test "pending within limit: does not call fail_music! on order" do
    mg      = music_generation_in_polling_state(poll_count: 0)
    order   = mg.order
    pending = status_result(status: "pending")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { pending }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_not_equal "music_failed", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Status: pending — at poll limit (gives up)
  # ---------------------------------------------------------------------------

  test "pending at poll limit: calls fail_music! on order" do
    mg      = music_generation_in_polling_state(poll_count: 40)
    order   = mg.order
    pending = status_result(status: "pending")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { pending }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "music_failed", order.reload.status
  end

  test "pending at poll limit: does not re-enqueue PollMurekaStatusJob" do
    mg      = music_generation_in_polling_state(poll_count: 40)
    pending = status_result(status: "pending")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { pending }) do
      assert_no_enqueued_jobs(only: PollMurekaStatusJob) do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Status: succeeded
  # ---------------------------------------------------------------------------

  test "succeeded: creates 2 OrderAsset records" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      assert_difference "OrderAsset.count", 2 do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  test "succeeded: first OrderAsset has kind music_variant" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal "music_variant", assets.first.kind
  end

  test "succeeded: first OrderAsset has variant_index 0" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal 0, assets.first.variant_index
  end

  test "succeeded: second OrderAsset has variant_index 1" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal 1, assets.last.variant_index
  end

  test "succeeded: first OrderAsset has correct provider_url" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal "https://cdn.mureka.ai/song1.mp3", assets.first.provider_url
  end

  test "succeeded: first OrderAsset has correct flac_url" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal "https://cdn.mureka.ai/song1.flac", assets.first.flac_url
  end

  test "succeeded: first OrderAsset has correct wav_url" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal "https://cdn.mureka.ai/song1.wav", assets.first.wav_url
  end

  test "succeeded: first OrderAsset has correct duration_ms" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assets = OrderAsset.where(music_generation: mg).order(variant_index: :asc)
    assert_equal 180_000, assets.first.duration_ms
  end

  test "succeeded: calls music_ready! on order" do
    mg        = music_generation_in_polling_state
    order     = mg.order
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "preview_ready", order.reload.status
  end

  test "succeeded: updates music_generation status to completed" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "completed", mg.reload.status
  end

  test "succeeded: does not re-enqueue PollMurekaStatusJob" do
    mg        = music_generation_in_polling_state
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      assert_no_enqueued_jobs(only: PollMurekaStatusJob) do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Status: failed (Mureka reports failure)
  # ---------------------------------------------------------------------------

  test "mureka failed status: calls fail_music! on order" do
    mg     = music_generation_in_polling_state
    order  = mg.order
    failed = status_result(status: "failed")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { failed }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "music_failed", order.reload.status
  end

  test "mureka failed status: updates music_generation status to failed" do
    mg     = music_generation_in_polling_state
    failed = status_result(status: "failed")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { failed }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "failed", mg.reload.status
  end

  test "mureka failed status: does not create OrderAssets" do
    mg     = music_generation_in_polling_state
    failed = status_result(status: "failed")

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { failed }) do
      assert_no_difference "OrderAsset.count" do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Client failure (network / API error)
  # ---------------------------------------------------------------------------

  test "client failure: calls fail_music! on order" do
    mg    = music_generation_in_polling_state
    order = mg.order

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { failure_result }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "music_failed", order.reload.status
  end

  test "client failure: updates music_generation status to failed" do
    mg = music_generation_in_polling_state

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { failure_result }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "failed", mg.reload.status
  end

  test "client failure: does not create OrderAssets" do
    mg = music_generation_in_polling_state

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { failure_result }) do
      assert_no_difference "OrderAsset.count" do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # MusicGeneration not found
  # ---------------------------------------------------------------------------

  test "raises ActiveRecord::RecordNotFound when music_generation_id does not exist" do
    assert_raises(ActiveRecord::RecordNotFound) do
      PollMurekaStatusJob.perform_now(99_999_999)
    end
  end

  # ---------------------------------------------------------------------------
  # Turbo Stream broadcast on succeeded
  # ---------------------------------------------------------------------------

  test "succeeded: broadcasts a Turbo Stream replacing music_section on the order's music channel" do
    mg        = music_generation_in_polling_state
    order     = mg.order
    succeeded = status_result(status: "succeeded", choices: TWO_CHOICES)
    channel   = "order_#{order.id}_music"

    MusicGenerator::MurekaStatusClient.stub(:call, ->(**_args) { succeeded }) do
      assert_broadcasts(channel, 1) do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Soundtrack generation_type routing
  # ---------------------------------------------------------------------------

  SOUNDTRACK_CHOICE = [
    { url: "https://cdn.mureka.ai/soundtrack.mp4", duration_ms: 30_000 }
  ].freeze

  def soundtrack_result(status:, choices: nil)
    ServiceResult.new(success: true, value: { status: status, choices: choices }, errors: nil)
  end

  test "uses MurekaSoundtrackStatusClient when generation_type is soundtrack" do
    mg = music_generation_in_polling_state
    mg.update_columns(generation_type: "soundtrack")
    pending_result = soundtrack_result(status: "pending")

    called_with_soundtrack_client = false
    MusicGenerator::MurekaSoundtrackStatusClient.stub(:call, ->(**_args) {
      called_with_soundtrack_client = true
      pending_result
    }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert called_with_soundtrack_client, "Expected MurekaSoundtrackStatusClient to be called"
  end

  test "soundtrack succeeded: creates one OrderAsset with kind soundtrack_video" do
    mg = music_generation_in_polling_state
    mg.update_columns(generation_type: "soundtrack")
    succeeded = soundtrack_result(status: "succeeded", choices: SOUNDTRACK_CHOICE)

    MusicGenerator::MurekaSoundtrackStatusClient.stub(:call, ->(**_args) { succeeded }) do
      assert_difference "OrderAsset.count", 1 do
        PollMurekaStatusJob.perform_now(mg.id)
      end
    end

    asset = OrderAsset.where(music_generation: mg).last
    assert_equal "soundtrack_video", asset.kind
    assert_equal 0, asset.variant_index
    assert_equal "https://cdn.mureka.ai/soundtrack.mp4", asset.provider_url
    assert_equal 30_000, asset.duration_ms
  end

  test "soundtrack succeeded: transitions order to preview_ready" do
    mg    = music_generation_in_polling_state
    order = mg.order
    mg.update_columns(generation_type: "soundtrack")
    succeeded = soundtrack_result(status: "succeeded", choices: SOUNDTRACK_CHOICE)

    MusicGenerator::MurekaSoundtrackStatusClient.stub(:call, ->(**_args) { succeeded }) do
      PollMurekaStatusJob.perform_now(mg.id)
    end

    assert_equal "preview_ready", order.reload.status
  end
end
