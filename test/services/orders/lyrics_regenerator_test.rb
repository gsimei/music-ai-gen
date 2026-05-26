# frozen_string_literal: true

require "test_helper"

# Tests for Orders::LyricsRegenerator — validates regen eligibility and enqueues
# GenerateLyricsJob in "regen" mode with the current draft and optional feedback.
#
# Service interface:
#   Orders::LyricsRegenerator.call(order:, user_feedback:)
#
# Returns ServiceResult:
#   success? => true,  value: nil (side effect: job enqueued)
#   success? => false, errors: :invalid_state | :regen_limit_reached
class Orders::LyricsRegeneratorTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Happy path — order is lyrics_ready and regen limit is not exhausted
  # ---------------------------------------------------------------------------

  test "returns success_result when order is lyrics_ready and limit not exhausted" do
    order = orders(:b2c_lyrics_ready) # lyrics_regen_used: 0, limit: 2

    result = Orders::LyricsRegenerator.call(order: order, user_feedback: "Piu romantica")

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "enqueues GenerateLyricsJob with mode regen on success" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    assert_enqueued_with(job: GenerateLyricsJob) do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "Piu romantica")
    end
  end

  test "enqueues GenerateLyricsJob with correct order_id on success" do
    order = orders(:b2c_lyrics_ready)

    assert_enqueued_with(job: GenerateLyricsJob, args: [order.id]) do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "Piu romantica")
    end
  end

  test "enqueues GenerateLyricsJob with mode regen keyword argument" do
    order = orders(:b2c_lyrics_ready)

    assert_enqueued_with(job: GenerateLyricsJob, kwargs: hash_including(mode: "regen")) do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "Piu romantica")
    end
  end

  test "enqueues GenerateLyricsJob with parent_draft_id of the latest draft" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    assert_enqueued_with(job: GenerateLyricsJob, kwargs: hash_including(parent_draft_id: draft.id)) do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "Piu romantica")
    end
  end

  test "enqueues GenerateLyricsJob with user_feedback passed through" do
    order = orders(:b2c_lyrics_ready)

    assert_enqueued_with(job: GenerateLyricsJob, kwargs: hash_including(user_feedback: "Piu romantica")) do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "Piu romantica")
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — user_feedback is nil (feedback is optional)
  # ---------------------------------------------------------------------------

  test "succeeds when user_feedback is nil" do
    order = orders(:b2c_lyrics_ready)

    result = Orders::LyricsRegenerator.call(order: order, user_feedback: nil)

    assert result.success?, "Expected success with nil feedback"
  end

  test "enqueues GenerateLyricsJob when user_feedback is nil" do
    order = orders(:b2c_lyrics_ready)

    assert_enqueued_with(job: GenerateLyricsJob, kwargs: hash_including(user_feedback: nil)) do
      Orders::LyricsRegenerator.call(order: order, user_feedback: nil)
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — order is not in lyrics_ready state
  # ---------------------------------------------------------------------------

  test "returns failure_result with :invalid_state when order is not lyrics_ready" do
    order = orders(:b2c_lyrics_drafting)

    result = Orders::LyricsRegenerator.call(order: order, user_feedback: "anything")

    assert result.failure?
    assert_equal :invalid_state, result.errors
  end

  test "does not enqueue GenerateLyricsJob when order is not lyrics_ready" do
    order = orders(:b2c_lyrics_drafting)

    assert_no_enqueued_jobs only: GenerateLyricsJob do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "anything")
    end
  end

  test "returns failure_result with :invalid_state when order is lyrics_approved" do
    order = orders(:b2c_lyrics_approved)

    result = Orders::LyricsRegenerator.call(order: order, user_feedback: "anything")

    assert result.failure?
    assert_equal :invalid_state, result.errors
  end

  # ---------------------------------------------------------------------------
  # Failure — regen limit exhausted
  # ---------------------------------------------------------------------------

  test "returns failure_result with :regen_limit_reached when limit exhausted" do
    order = orders(:b2c_lyrics_ready_at_limit) # lyrics_regen_used: 2, limit: 2

    result = Orders::LyricsRegenerator.call(order: order, user_feedback: "terceira vez")

    assert result.failure?
    assert_equal :regen_limit_reached, result.errors
  end

  test "does not enqueue GenerateLyricsJob when regen limit is exhausted" do
    order = orders(:b2c_lyrics_ready_at_limit)

    assert_no_enqueued_jobs only: GenerateLyricsJob do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "terceira vez")
    end
  end

  test "does not enqueue GenerateLyricsJob when order state is wrong, even if limit allows" do
    order = orders(:b2c_paid) # paid state — regen_used: 0

    assert_no_enqueued_jobs only: GenerateLyricsJob do
      Orders::LyricsRegenerator.call(order: order, user_feedback: "anything")
    end
  end
end
