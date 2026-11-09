# frozen_string_literal: true

require "test_helper"

# Tests for GenerateMusicJob
#
# Responsibilities:
# - Queued on the :ai queue
# - Finds Order by order_id; raises ActiveRecord::RecordNotFound if missing
#   (lets Solid Queue retry / discard according to job config)
# - Calls order.start_music_generation! (AASM transition: lyrics_approved → music_generating)
# - Calls MusicGenerator::Generator.call(order:)
# - On success: no further action (Generator already enqueued PollMurekaStatusJob)
# - On failure: calls order.fail_music! (AASM transition: music_generating → music_failed)
#
# Job interface:
#   GenerateMusicJob.perform_later(order_id)
#
# PREREQUISITE: The following fixture must exist (see generator_test.rb for full spec):
#   test/fixtures/briefings.yml — b2c_lyrics_approved_briefing (order: b2c_lyrics_approved, voice: standard_voice, ...)
class GenerateMusicJobTest < ActiveJob::TestCase
  # ---------------------------------------------------------------------------
  # Queue
  # ---------------------------------------------------------------------------

  test "job is queued on the :ai queue" do
    assert_equal :ai, GenerateMusicJob.queue_name.to_sym
  end

  # ---------------------------------------------------------------------------
  # Happy path — successful generation
  # ---------------------------------------------------------------------------

  test "success: order transitions to music_generating after start_music_generation!" do
    order          = orders(:b2b_lyrics_approved)
    music_gen      = MusicGeneration.new(
      order:       order,
      mureka_job_id: "job_abc123",
      status:      "pending",
      provider:    "mureka",
      model:       "auto"
    )
    success_result = ServiceResult.new(success: true, value: music_gen, errors: nil)

    MusicGenerator::Generator.stub(:call, ->(**_args) { success_result }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_equal "music_generating", order.reload.status
  end

  test "success: Generator is called with the correct order" do
    order          = orders(:b2b_lyrics_approved)
    captured_order = nil

    music_gen      = MusicGeneration.new(
      order:       order,
      mureka_job_id: "job_abc123",
      status:      "pending",
      provider:    "mureka",
      model:       "auto"
    )
    success_result = ServiceResult.new(success: true, value: music_gen, errors: nil)

    MusicGenerator::Generator.stub(:call, lambda { |**args|
      captured_order = args[:order]
      success_result
    }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_equal order.id, captured_order.id
  end

  test "success: order is in music_generating state when Generator is called" do
    order               = orders(:b2b_lyrics_approved)
    status_at_call      = nil

    music_gen           = MusicGeneration.new(
      order:          order,
      mureka_job_id:  "job_abc123",
      status:         "pending",
      provider:       "mureka",
      model:          "auto"
    )
    success_result      = ServiceResult.new(success: true, value: music_gen, errors: nil)

    MusicGenerator::Generator.stub(:call, lambda { |**args|
      status_at_call = args[:order].reload.status
      success_result
    }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_equal "music_generating", status_at_call,
                 "Order should be in music_generating state when Generator is called"
  end

  test "success: order does NOT transition to music_failed" do
    order          = orders(:b2b_lyrics_approved)
    music_gen      = MusicGeneration.new(
      order:         order,
      mureka_job_id: "job_abc123",
      status:        "pending",
      provider:      "mureka",
      model:         "auto"
    )
    success_result = ServiceResult.new(success: true, value: music_gen, errors: nil)

    MusicGenerator::Generator.stub(:call, ->(**_args) { success_result }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_not_equal "music_failed", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Failure path — Generator returns failure
  # ---------------------------------------------------------------------------

  test "generator failure: order transitions to music_failed" do
    order          = orders(:b2b_lyrics_approved)
    failure_result = ServiceResult.new(success: false, value: nil, errors: :api_error)

    MusicGenerator::Generator.stub(:call, ->(**_args) { failure_result }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_equal "music_failed", order.reload.status
  end

  test "generator failure: order does not end in music_generating" do
    order          = orders(:b2b_lyrics_approved)
    failure_result = ServiceResult.new(success: false, value: nil, errors: :api_error)

    MusicGenerator::Generator.stub(:call, ->(**_args) { failure_result }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_not_equal "music_generating", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Order not found
  # ---------------------------------------------------------------------------

  test "raises ActiveRecord::RecordNotFound when order_id does not exist" do
    assert_raises(ActiveRecord::RecordNotFound) do
      GenerateMusicJob.perform_now(99_999_999)
    end
  end

  # ---------------------------------------------------------------------------
  # melody_hint keyword argument — forwarded to Generator
  # ---------------------------------------------------------------------------

  test "melody_hint keyword argument is forwarded to MusicGenerator::Generator" do
    order           = orders(:b2b_lyrics_approved)
    hint            = "Uplifting, piano-led, moderate tempo"
    captured_hint   = nil

    music_gen      = MusicGeneration.new(
      order:         order,
      mureka_job_id: "job_hint_test",
      status:        "pending",
      provider:      "mureka",
      model:         "auto"
    )
    success_result = ServiceResult.new(success: true, value: music_gen, errors: nil)

    MusicGenerator::Generator.stub(:call, lambda { |**args|
      captured_hint = args[:melody_hint]
      success_result
    }) do
      GenerateMusicJob.perform_now(order.id, melody_hint: hint)
    end

    assert_equal hint, captured_hint,
                 "Expected melody_hint to be forwarded to Generator"
  end

  test "melody_hint is nil when not provided to the job" do
    order          = orders(:b2b_lyrics_approved)
    captured_hint  = :not_set

    music_gen      = MusicGeneration.new(
      order:         order,
      mureka_job_id: "job_no_hint",
      status:        "pending",
      provider:      "mureka",
      model:         "auto"
    )
    success_result = ServiceResult.new(success: true, value: music_gen, errors: nil)

    MusicGenerator::Generator.stub(:call, lambda { |**args|
      captured_hint = args[:melody_hint]
      success_result
    }) do
      GenerateMusicJob.perform_now(order.id)
    end

    assert_nil captured_hint,
               "Expected melody_hint to be nil when not passed to job"
  end
end
