# frozen_string_literal: true

require "test_helper"

# Tests for Stripe::Handlers::ChargeRefunded
#
# Responsibilities:
# - Finds order by stripe_payment_intent_id from the charge payload
# - Full refund (amount == amount_refunded):
#     * Creates RefundRequest (only if order.user is present and not a guest)
#     * Calls order.cancel! then order.refund! (AASM events)
# - Partial refund (amount > amount_refunded):
#     * Creates RefundRequest if user present
#     * Does NOT cancel/refund the order
# - Guest order (user is nil OR user.guest? == true):
#     * Does NOT create RefundRequest
#     * Still cancels+refunds on full refund
# - Order not found → success_result(:no_order_found)
class Stripe::Handlers::ChargeRefundedTest < ActiveSupport::TestCase
  setup do
    # b2c_paid_with_stripe: status=paid, user=customer_b2c (not guest)
    @paid_order = orders(:b2c_paid_with_stripe)
    # stripe_payment_intent_id: "pi_test_paid_intent_001"
  end

  # ---------------------------------------------------------------------------
  # Full refund — paid order with non-guest user
  # ---------------------------------------------------------------------------

  test "full refund on paid order creates RefundRequest" do
    event = build_charge_refunded_event(
      "evt_full_refund_001",
      payment_intent_id: @paid_order.stripe_payment_intent_id,
      amount: 1900,
      amount_refunded: 1900
    )

    assert_difference "RefundRequest.count", 1 do
      result = Stripe::Handlers::ChargeRefunded.call(stripe_event: event)
      assert result.success?, "Expected success_result, got: #{result.errors.inspect}"
    end
  end

  test "full refund on paid order transitions order to cancelled then refunded" do
    event = build_charge_refunded_event(
      "evt_full_refund_002",
      payment_intent_id: @paid_order.stripe_payment_intent_id,
      amount: 1900,
      amount_refunded: 1900
    )

    Stripe::Handlers::ChargeRefunded.call(stripe_event: event)

    assert_equal "refunded", @paid_order.reload.status
  end

  test "full refund RefundRequest belongs to the order user" do
    event = build_charge_refunded_event(
      "evt_full_refund_003",
      payment_intent_id: @paid_order.stripe_payment_intent_id,
      amount: 1900,
      amount_refunded: 1900
    )

    Stripe::Handlers::ChargeRefunded.call(stripe_event: event)

    refund_request = RefundRequest.where(order: @paid_order).last
    assert_not_nil refund_request
    assert_equal @paid_order.user_id, refund_request.user_id
  end

  # ---------------------------------------------------------------------------
  # Partial refund — RefundRequest created but order NOT cancelled
  # ---------------------------------------------------------------------------

  test "partial refund creates RefundRequest but does not cancel order" do
    event = build_charge_refunded_event(
      "evt_partial_refund_001",
      payment_intent_id: @paid_order.stripe_payment_intent_id,
      amount: 1900,
      amount_refunded: 500   # partial
    )

    assert_difference "RefundRequest.count", 1 do
      result = Stripe::Handlers::ChargeRefunded.call(stripe_event: event)
      assert result.success?
    end

    assert_equal "paid", @paid_order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Guest order — no RefundRequest, but still cancel+refund on full refund
  # ---------------------------------------------------------------------------

  test "full refund on guest order does not create RefundRequest" do
    # guest_order is pending in fixture — need a paid guest order
    guest_order = orders(:guest_order)
    guest_order.update_columns(
      status: "paid",
      stripe_payment_intent_id: "pi_test_guest_paid_001"
    )

    # guest_user has guest: true in fixture
    assert guest_order.user.guest?, "guest_order user must be a guest"

    event = build_charge_refunded_event(
      "evt_guest_refund_001",
      payment_intent_id: "pi_test_guest_paid_001",
      amount: 1900,
      amount_refunded: 1900
    )

    assert_no_difference "RefundRequest.count" do
      result = Stripe::Handlers::ChargeRefunded.call(stripe_event: event)
      assert result.success?
    end
  end

  test "full refund on guest order still cancels and refunds the order" do
    guest_order = orders(:guest_order)
    guest_order.update_columns(
      status: "paid",
      stripe_payment_intent_id: "pi_test_guest_paid_002"
    )

    event = build_charge_refunded_event(
      "evt_guest_refund_002",
      payment_intent_id: "pi_test_guest_paid_002",
      amount: 1900,
      amount_refunded: 1900
    )

    Stripe::Handlers::ChargeRefunded.call(stripe_event: event)

    assert_equal "refunded", guest_order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Order not found
  # ---------------------------------------------------------------------------

  test "charge refunded with unknown payment_intent_id returns success(:no_order_found)" do
    event = build_charge_refunded_event(
      "evt_refund_notfound_001",
      payment_intent_id: "pi_test_does_not_exist_999",
      amount: 1900,
      amount_refunded: 1900
    )

    result = Stripe::Handlers::ChargeRefunded.call(stripe_event: event)

    assert result.success?
    assert_equal :no_order_found, result.value
  end

  test "missing payment_intent in charge payload returns success(:no_order_found)" do
    event = StripeEvent.create!(
      stripe_event_id: "evt_refund_no_pi_001",
      event_type: "charge.refunded",
      status: "pending",
      payload: {
        id: "evt_refund_no_pi_001",
        type: "charge.refunded",
        data: {
          object: {
            id: "ch_test_no_pi_001",
            object: "charge",
            amount: 1900,
            amount_refunded: 1900
            # no payment_intent key
          }
        }
      }
    )

    result = Stripe::Handlers::ChargeRefunded.call(stripe_event: event)

    assert result.success?
    assert_equal :no_order_found, result.value
  end

  private

  def build_charge_refunded_event(event_id, payment_intent_id:, amount:, amount_refunded:)
    StripeEvent.create!(
      stripe_event_id: event_id,
      event_type: "charge.refunded",
      status: "pending",
      payload: {
        id: event_id,
        type: "charge.refunded",
        data: {
          object: {
            id: "ch_test_#{SecureRandom.hex(4)}",
            object: "charge",
            payment_intent: payment_intent_id,
            amount: amount,
            amount_refunded: amount_refunded
          }
        }
      }
    )
  end
end
