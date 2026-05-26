# frozen_string_literal: true

require "test_helper"

# Tests for Orders::LyricsApprover — approves a lyrics draft and fires the
# approve_lyrics! AASM event on the order.
#
# Service interface:
#   Orders::LyricsApprover.call(order:, draft_id:)
#
# Returns ServiceResult:
#   success? => true,  value: order (reloaded, status == "lyrics_approved")
#   success? => false, errors: symbol or ActiveModel::Errors describing the failure
class Orders::LyricsApproverTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Happy path — order is lyrics_ready, draft belongs to order and is unlocked
  # ---------------------------------------------------------------------------

  test "returns success_result when order is lyrics_ready and draft is valid" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "order status transitions to lyrics_approved on success" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert_equal "lyrics_approved", order.reload.status
  end

  test "draft is_locked becomes true on success" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert draft.reload.is_locked, "Expected draft to be locked after approval"
  end

  test "draft is_approved becomes true on success" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert draft.reload.is_approved, "Expected draft to be approved after approval"
  end

  test "order approved_lyrics_draft_id is set to the draft id on success" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert_equal draft.id, order.reload.approved_lyrics_draft_id
  end

  # ---------------------------------------------------------------------------
  # Failure — order is not in lyrics_ready state
  # ---------------------------------------------------------------------------

  test "returns failure_result when order is not in lyrics_ready state" do
    order = orders(:b2c_lyrics_drafting)
    draft = lyrics_drafts(:draft_v1)

    result = Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert result.failure?, "Expected failure for non-lyrics_ready order"
  end

  test "order status does not change when order is not in lyrics_ready state" do
    order = orders(:b2c_lyrics_drafting)
    draft = lyrics_drafts(:draft_v1)

    Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert_equal "lyrics_drafting", order.reload.status
  end

  test "returns failure_result when order is already lyrics_approved" do
    order = orders(:b2c_lyrics_approved)
    # draft_approved belongs to b2c_delivered, not b2c_lyrics_approved, but
    # the state guard fires first — we just need any draft_id to exercise the path
    draft = lyrics_drafts(:draft_approved)

    result = Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert result.failure?, "Expected failure for already-approved order"
  end

  # ---------------------------------------------------------------------------
  # Failure — draft does not exist
  # ---------------------------------------------------------------------------

  test "returns failure_result when draft_id does not exist" do
    order = orders(:b2c_lyrics_ready)

    result = Orders::LyricsApprover.call(order: order, draft_id: 0)

    assert result.failure?, "Expected failure for non-existent draft_id"
  end

  test "order status does not change when draft_id does not exist" do
    order = orders(:b2c_lyrics_ready)

    Orders::LyricsApprover.call(order: order, draft_id: 0)

    assert_equal "lyrics_ready", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Failure — draft belongs to a different order
  # ---------------------------------------------------------------------------

  test "returns failure_result when draft belongs to a different order" do
    order   = orders(:b2c_lyrics_ready)
    # draft_v1 belongs to b2c_paid, NOT b2c_lyrics_ready
    other_draft = lyrics_drafts(:draft_v1)

    result = Orders::LyricsApprover.call(order: order, draft_id: other_draft.id)

    assert result.failure?, "Expected failure when draft belongs to a different order"
  end

  test "order status does not change when draft belongs to a different order" do
    order       = orders(:b2c_lyrics_ready)
    other_draft = lyrics_drafts(:draft_v1)

    Orders::LyricsApprover.call(order: order, draft_id: other_draft.id)

    assert_equal "lyrics_ready", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Failure — draft is already locked / approved
  # ---------------------------------------------------------------------------

  test "returns failure_result when draft is already locked" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)
    # Manually lock the draft to simulate a double-approval attempt
    draft.update_columns(is_locked: true, is_approved: true)

    result = Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert result.failure?, "Expected failure when draft is already locked"
  end

  test "order status does not change when draft is already locked" do
    order = orders(:b2c_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)
    draft.update_columns(is_locked: true, is_approved: true)

    Orders::LyricsApprover.call(order: order, draft_id: draft.id)

    assert_equal "lyrics_ready", order.reload.status
  end
end
