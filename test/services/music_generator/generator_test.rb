# frozen_string_literal: true

require "test_helper"

# Stub the MusicGenerator namespace so the test file loads even before
# the implementation exists.  Tests will still fail with NameError on
# MusicGenerator::Generator until the class is implemented.
module MusicGenerator; end unless defined?(MusicGenerator)

# Tests for MusicGenerator::Generator
#
# Responsibilities:
# - Validates guards before calling Mureka: order in lyrics_approved state,
#   order has a current draft, order has a briefing, briefing has a voice
# - Calls MurekaClient.call(prompt:, lyrics:, voice_id:)
# - Creates a MusicGeneration record with mureka_job_id, status "pending",
#   provider "mureka", model "auto"
# - Enqueues PollMurekaStatusJob.perform_later(music_generation.id)
# - Returns success_result(music_generation) on success
# - Returns failure_result on guard violations or client failure
#
# Service interface:
#   MusicGenerator::Generator.call(order: Order)
#
# Returns ServiceResult:
#   success? => true,  value: MusicGeneration instance
#   success? => false, errors: Symbol
#
# PREREQUISITE: The following fixtures must be added before tests will pass:
#   test/fixtures/briefings.yml — b2c_lyrics_approved_briefing:
#     order: b2c_lyrics_approved
#     voice: standard_voice
#     about: "Uma musica especial para o aniversario da minha mae"
#     recipient: "Maria"
#     occasion: "birthday"
#     music_style: "pop"
#     mood: "happy"
#     tempo: "moderate"
#     target_duration_seconds: 120
#     language: "it"
#
#   test/fixtures/lyrics_drafts.yml — draft_lyrics_approved_v1:
#     order: b2c_lyrics_approved
#     version: 1
#     source: "ai_generated"
#     content: "Buon compleanno cara mamma\nSei la mia stella"
#     is_approved: false
#     is_locked: false
class MusicGenerator::GeneratorTest < ActiveSupport::TestCase
  # Stub MurekaClient success
  def stub_mureka_client_success(job_id: "job_abc123")
    success = ServiceResult.new(success: true, value: { job_id: job_id }, errors: nil)
    MusicGenerator::MurekaClient.stub(:call, ->(**_args) { success }) do
      yield
    end
  end

  # Stub MurekaClient failure
  def stub_mureka_client_failure
    failure = ServiceResult.new(success: false, value: nil, errors: :api_error)
    MusicGenerator::MurekaClient.stub(:call, ->(**_args) { failure }) do
      yield
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — order in lyrics_approved with briefing and voice
  # ---------------------------------------------------------------------------

  test "returns success when order is lyrics_approved with briefing and voice" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?, "Expected success but got: #{result.errors.inspect}"
    end
  end

  test "creates one MusicGeneration record on success" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      assert_difference "MusicGeneration.count", 1 do
        MusicGenerator::Generator.call(order: order)
      end
    end
  end

  test "MusicGeneration has provider mureka" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_equal "mureka", result.value.provider
    end
  end

  test "MusicGeneration has model auto" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_equal "auto", result.value.model
    end
  end

  test "MusicGeneration has status pending" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_equal "pending", result.value.status
    end
  end

  test "MusicGeneration has mureka_job_id from client response" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success(job_id: "job_xyz999") do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_equal "job_xyz999", result.value.mureka_job_id
    end
  end

  test "MusicGeneration is associated with the order" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_equal order.id, result.value.order_id
    end
  end

  test "MusicGeneration has voice_id from briefing" do
    order = orders(:b2b_music_generating)
    expected_voice_id = order.briefing.voice_id

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_equal expected_voice_id, result.value.voice_id
    end
  end

  test "result value is a persisted MusicGeneration instance" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_kind_of MusicGeneration, result.value
      assert result.value.persisted?
    end
  end

  test "enqueues PollMurekaStatusJob after creating MusicGeneration" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      assert_enqueued_with(job: PollMurekaStatusJob) do
        MusicGenerator::Generator.call(order: order)
      end
    end
  end

  test "PollMurekaStatusJob is enqueued with the new music_generation id" do
    order = orders(:b2b_music_generating)
    music_generation_id = nil

    stub_mureka_client_success do
      MusicGenerator::Generator.call(order: order).tap do |result|
        music_generation_id = result.value.id
      end
    end

    assert_enqueued_with(job: PollMurekaStatusJob, args: [music_generation_id])
  end

  test "MurekaClient is called with prompt and lyrics" do
    order = orders(:b2b_music_generating)
    captured_args = nil

    success = ServiceResult.new(success: true, value: { job_id: "job_abc" }, errors: nil)
    MusicGenerator::MurekaClient.stub(:call, lambda { |**args|
      captured_args = args
      success
    }) do
      MusicGenerator::Generator.call(order: order)
    end

    assert_not_nil captured_args[:prompt], "Expected prompt to be passed to MurekaClient"
    assert_not_nil captured_args[:lyrics], "Expected lyrics to be passed to MurekaClient"
  end

  test "prompt includes no-intro instruction when briefing duration <= 60s" do
    order = orders(:b2b_music_generating)
    order.briefing.update_columns(target_duration_seconds: 30)
    captured_prompt = nil

    success = ServiceResult.new(success: true, value: { job_id: "job_abc" }, errors: nil)
    MusicGenerator::MurekaClient.stub(:call, lambda { |**args|
      captured_prompt = args[:prompt]
      success
    }) do
      MusicGenerator::Generator.call(order: order.reload)
    end

    assert_includes captured_prompt, "vocals start immediately"
  end

  test "prompt does NOT include no-intro instruction when briefing duration > 60s" do
    order = orders(:b2b_music_generating)
    order.briefing.update_columns(target_duration_seconds: 90)
    captured_prompt = nil

    success = ServiceResult.new(success: true, value: { job_id: "job_abc" }, errors: nil)
    MusicGenerator::MurekaClient.stub(:call, lambda { |**args|
      captured_prompt = args[:prompt]
      success
    }) do
      MusicGenerator::Generator.call(order: order.reload)
    end

    refute_includes captured_prompt, "vocals start immediately"
  end

  test "MurekaClient is called with voice_id from briefing" do
    order = orders(:b2b_music_generating)
    captured_voice_id = nil
    expected_external_id = order.briefing.voice.external_id

    success = ServiceResult.new(success: true, value: { job_id: "job_abc" }, errors: nil)
    MusicGenerator::MurekaClient.stub(:call, lambda { |**args|
      captured_voice_id = args[:voice_id]
      success
    }) do
      MusicGenerator::Generator.call(order: order)
    end

    assert_equal expected_external_id, captured_voice_id
  end

  # ---------------------------------------------------------------------------
  # Failure — order not in music_generating state
  # ---------------------------------------------------------------------------

  test "returns failure when order is not in music_generating state" do
    order = orders(:b2b_lyrics_approved)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.failure?, "Expected failure when order is not in music_generating state"
    end
  end

  test "error is :invalid_state when order is not in music_generating state" do
    order = orders(:b2b_lyrics_approved)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.failure?
      assert_equal :invalid_state, result.errors
    end
  end

  test "does not create MusicGeneration when order is in wrong state" do
    order = orders(:b2b_lyrics_approved)

    stub_mureka_client_success do
      assert_no_difference "MusicGeneration.count" do
        MusicGenerator::Generator.call(order: order)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — briefing has no voice
  # ---------------------------------------------------------------------------

  test "returns failure when briefing has no voice" do
    order = orders(:b2b_music_generating)
    # Remove voice from briefing without triggering other validations
    order.briefing.update_columns(voice_id: nil)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order.reload)
      assert result.failure?, "Expected failure when briefing has no voice"
    end
  end

  test "error is :no_voice when briefing has no voice" do
    order = orders(:b2b_music_generating)
    order.briefing.update_columns(voice_id: nil)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order.reload)
      assert result.failure?
      assert_equal :no_voice, result.errors
    end
  end

  test "does not create MusicGeneration when briefing has no voice" do
    order = orders(:b2b_music_generating)
    order.briefing.update_columns(voice_id: nil)

    stub_mureka_client_success do
      assert_no_difference "MusicGeneration.count" do
        MusicGenerator::Generator.call(order: order.reload)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — MurekaClient returns failure
  # ---------------------------------------------------------------------------

  test "returns failure when MurekaClient fails" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_failure do
      result = MusicGenerator::Generator.call(order: order)
      assert result.failure?, "Expected failure when MurekaClient fails"
    end
  end

  test "does not create MusicGeneration when MurekaClient fails" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_failure do
      assert_no_difference "MusicGeneration.count" do
        MusicGenerator::Generator.call(order: order)
      end
    end
  end

  test "does not enqueue PollMurekaStatusJob when MurekaClient fails" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_failure do
      assert_no_enqueued_jobs(only: PollMurekaStatusJob) do
        MusicGenerator::Generator.call(order: order)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # melody_hint — passed through to MurekaClient and persisted on MusicGeneration
  # ---------------------------------------------------------------------------

  test "melody_hint is forwarded to MurekaClient when provided" do
    order          = orders(:b2b_music_generating)
    hint           = "Uplifting, piano-led, moderate tempo"
    captured_hint  = nil

    success = ServiceResult.new(success: true, value: { job_id: "job_abc" }, errors: nil)
    MusicGenerator::MurekaClient.stub(:call, lambda { |**args|
      captured_hint = args[:melody_hint]
      success
    }) do
      MusicGenerator::Generator.call(order: order, melody_hint: hint)
    end

    assert_equal hint, captured_hint
  end

  test "created MusicGeneration has melody_hint set when provided" do
    order = orders(:b2b_music_generating)
    hint  = "Uplifting, piano-led"

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order, melody_hint: hint)
      assert result.success?
      assert_equal hint, result.value.melody_hint
    end
  end

  test "created MusicGeneration has nil melody_hint when not provided" do
    order = orders(:b2b_music_generating)

    stub_mureka_client_success do
      result = MusicGenerator::Generator.call(order: order)
      assert result.success?
      assert_nil result.value.melody_hint
    end
  end
end
