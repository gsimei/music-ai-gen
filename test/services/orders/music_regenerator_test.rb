# frozen_string_literal: true

require "test_helper"

# Tests for Orders::MusicRegenerator — validates regen eligibility and enqueues
# GenerateMusicJob with an optional melody_hint.
#
# Service interface:
#   Orders::MusicRegenerator.call(order:, melody_hint:)
#
# Returns ServiceResult:
#   success? => true,  value: nil (side effect: job enqueued, state transitioned)
#   success? => false, errors: :invalid_state | :regen_limit_reached
class Orders::MusicRegeneratorTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Happy path — order is preview_ready and regen limit is not exhausted
  # ---------------------------------------------------------------------------

  test "returns success_result when order is preview_ready and limit not exhausted" do
    order = orders(:b2b_preview_ready) # music_regen_used: 0, music_regen_limit: 1

    result = Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "transitions order to music_generating on success" do
    order = orders(:b2b_preview_ready)

    Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert_equal "music_generating", order.reload.status
  end

  test "increments music_regen_used by 1 on success" do
    order = orders(:b2b_preview_ready)
    original_used = order.music_regen_used

    Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert_equal original_used + 1, order.reload.music_regen_used
  end

  test "enqueues GenerateMusicJob with order.id on success" do
    order = orders(:b2b_preview_ready)

    assert_enqueued_with(job: GenerateMusicJob, args: [ order.id ]) do
      Orders::MusicRegenerator.call(order: order, melody_hint: nil)
    end
  end

  test "enqueues GenerateMusicJob with melody_hint keyword argument when provided" do
    order = orders(:b2b_preview_ready)
    hint  = "More energetic, faster tempo"

    assert_enqueued_with(job: GenerateMusicJob, kwargs: hash_including(melody_hint: hint)) do
      Orders::MusicRegenerator.call(order: order, melody_hint: hint)
    end
  end

  test "enqueues GenerateMusicJob with nil melody_hint when not provided" do
    order = orders(:b2b_preview_ready)

    assert_enqueued_with(job: GenerateMusicJob, kwargs: hash_including(melody_hint: nil)) do
      Orders::MusicRegenerator.call(order: order, melody_hint: nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — order is not in preview_ready state
  # ---------------------------------------------------------------------------

  test "returns failure_result with :invalid_state when order is not preview_ready" do
    order = orders(:b2b_approved)

    result = Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert result.failure?
    assert_equal :invalid_state, result.errors
  end

  test "returns failure_result with :invalid_state when order is lyrics_approved" do
    order = orders(:b2b_lyrics_approved)

    result = Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert result.failure?
    assert_equal :invalid_state, result.errors
  end

  test "does not enqueue GenerateMusicJob when order is not preview_ready" do
    order = orders(:b2b_approved)

    assert_no_enqueued_jobs only: GenerateMusicJob do
      Orders::MusicRegenerator.call(order: order, melody_hint: nil)
    end
  end

  test "does not transition state when order is not preview_ready" do
    order = orders(:b2b_approved)

    Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert_equal "approved", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Failure — regen limit exhausted
  # ---------------------------------------------------------------------------

  test "returns failure_result with :regen_limit_reached when music_regen_used >= music_regen_limit" do
    order = orders(:b2b_preview_ready_at_limit) # music_regen_used: 1, music_regen_limit: 1

    result = Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert result.failure?
    assert_equal :regen_limit_reached, result.errors
  end

  test "does NOT transition state when regen limit is reached" do
    order = orders(:b2b_preview_ready_at_limit)

    Orders::MusicRegenerator.call(order: order, melody_hint: nil)

    assert_equal "preview_ready", order.reload.status
  end

  test "does NOT enqueue job when regen limit is reached" do
    order = orders(:b2b_preview_ready_at_limit)

    assert_no_enqueued_jobs only: GenerateMusicJob do
      Orders::MusicRegenerator.call(order: order, melody_hint: nil)
    end
  end
end
