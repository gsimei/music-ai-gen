# frozen_string_literal: true

require "test_helper"

# Tests for Orders::MusicApprover — approves a music variant and fires the
# approve_music! AASM event on the order.
#
# Service interface:
#   Orders::MusicApprover.call(order:, variant:)
#
# Returns ServiceResult:
#   success? => true,  value: order (reloaded, status == "approved")
#   success? => false, errors: ActiveModel::Errors or symbol describing failure
#
# On success:
#   - order.approved_variant is set to the chosen variant ("a" or "b")
#   - order.approved_music_generation_id is set from the matching OrderAsset
#   - order.approve_music! AASM event fires, transitioning to "approved"
#   - DeliverOrderJob is enqueued (via after_commit on approve_music event)
class Orders::MusicApproverTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Happy path — variant "a" chosen
  # ---------------------------------------------------------------------------

  test "returns success_result when order is preview_ready and variant is a" do
    order = orders(:b2b_preview_ready)

    result = Orders::MusicApprover.call(order: order, variant: "a")

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "order status transitions to approved when variant a is chosen" do
    order = orders(:b2b_preview_ready)

    Orders::MusicApprover.call(order: order, variant: "a")

    assert_equal "approved", order.reload.status
  end

  test "order approved_variant is set to a when variant a is chosen" do
    order = orders(:b2b_preview_ready)

    Orders::MusicApprover.call(order: order, variant: "a")

    assert_equal "a", order.reload.approved_variant
  end

  test "order approved_music_generation_id is set from variant a asset music_generation" do
    order           = orders(:b2b_preview_ready)
    expected_gen_id = order_assets(:music_variant_a).music_generation_id

    Orders::MusicApprover.call(order: order, variant: "a")

    assert_equal expected_gen_id, order.reload.approved_music_generation_id
  end

  # ---------------------------------------------------------------------------
  # Happy path — variant "b" chosen
  # ---------------------------------------------------------------------------

  test "returns success_result when order is preview_ready and variant is b" do
    order = orders(:b2b_preview_ready)

    result = Orders::MusicApprover.call(order: order, variant: "b")

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "order status transitions to approved when variant b is chosen" do
    order = orders(:b2b_preview_ready)

    Orders::MusicApprover.call(order: order, variant: "b")

    assert_equal "approved", order.reload.status
  end

  test "order approved_variant is set to b when variant b is chosen" do
    order = orders(:b2b_preview_ready)

    Orders::MusicApprover.call(order: order, variant: "b")

    assert_equal "b", order.reload.approved_variant
  end

  test "order approved_music_generation_id is set from variant b asset music_generation" do
    order           = orders(:b2b_preview_ready)
    expected_gen_id = order_assets(:music_variant_b).music_generation_id

    Orders::MusicApprover.call(order: order, variant: "b")

    assert_equal expected_gen_id, order.reload.approved_music_generation_id
  end

  # ---------------------------------------------------------------------------
  # Failure — variant is blank
  # ---------------------------------------------------------------------------

  test "returns failure_result when variant is blank" do
    order = orders(:b2b_preview_ready)

    result = Orders::MusicApprover.call(order: order, variant: "")

    assert result.failure?, "Expected failure for blank variant"
  end

  test "order status does not change when variant is blank" do
    order = orders(:b2b_preview_ready)

    Orders::MusicApprover.call(order: order, variant: "")

    assert_equal "preview_ready", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Failure — variant is not in APPROVED_VARIANTS
  # ---------------------------------------------------------------------------

  test "returns failure_result when variant is not in APPROVED_VARIANTS" do
    order = orders(:b2b_preview_ready)

    result = Orders::MusicApprover.call(order: order, variant: "c")

    assert result.failure?, "Expected failure for invalid variant value"
  end

  test "order status does not change when variant is invalid" do
    order = orders(:b2b_preview_ready)

    Orders::MusicApprover.call(order: order, variant: "c")

    assert_equal "preview_ready", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Failure — order is not in preview_ready state
  # ---------------------------------------------------------------------------

  test "returns failure_result when order is not in preview_ready state" do
    order = orders(:b2b_pending)

    result = Orders::MusicApprover.call(order: order, variant: "a")

    assert result.failure?, "Expected failure for non-preview_ready order"
  end

  test "order status does not change when order is not in preview_ready state" do
    order = orders(:b2b_pending)

    Orders::MusicApprover.call(order: order, variant: "a")

    assert_equal "pending", order.reload.status
  end

  test "returns failure_result when order is already approved" do
    order = orders(:b2b_approved)

    result = Orders::MusicApprover.call(order: order, variant: "a")

    assert result.failure?, "Expected failure for order already in approved state"
  end
end
