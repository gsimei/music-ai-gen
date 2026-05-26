# frozen_string_literal: true

require "test_helper"

# Tests for Stripe::Handlers::PaymentIntentFailed
#
# Responsibilities:
# - Finds order by stripe_payment_intent_id from the event payload
# - Uses update_columns(status: "payment_failed") — NOT an AASM event
#   (allows transition from any state, bypasses validations)
# - Returns success_result on update
# - Returns success_result(:no_order_found) when no order matches the payment_intent_id
# - Returns success_result(:already_handled) when order is already payment_failed (idempotency)
class Stripe::Handlers::PaymentIntentFailedTest < ActiveSupport::TestCase
  setup do
    @pending_order = orders(:b2c_pending)
    @pending_order.update_columns(stripe_payment_intent_id: "pi_test_handler_pifail_001")

    @failed_order = orders(:b2c_payment_failed)
    # stripe_payment_intent_id: "pi_test_failed_intent_001" set in fixture
  end

  # ---------------------------------------------------------------------------
  # Happy path — pending order becomes payment_failed
  # ---------------------------------------------------------------------------

  test "pending order with matching payment_intent_id is set to payment_failed" do
    event = build_stripe_event("evt_pifail_pending_001", "pi_test_handler_pifail_001")

    result = Stripe::Handlers::PaymentIntentFailed.call(stripe_event: event)

    assert result.success?, "Expected success_result, got: #{result.errors.inspect}"
    assert_equal "payment_failed", @pending_order.reload.status
  end

  test "update uses update_columns bypassing AASM callbacks" do
    # Verify the order is updated even from a state that AASM does not have
    # a direct payment_failed transition from (e.g. lyrics_drafting would be blocked
    # by AASM but update_columns bypasses it)
    order_in_lyrics = orders(:b2c_lyrics_drafting)
    order_in_lyrics.update_columns(stripe_payment_intent_id: "pi_test_bypass_aasm_001")

    event = build_stripe_event("evt_pifail_bypass_001", "pi_test_bypass_aasm_001")

    result = Stripe::Handlers::PaymentIntentFailed.call(stripe_event: event)

    assert result.success?
    assert_equal "payment_failed", order_in_lyrics.reload.status
  end

  # ---------------------------------------------------------------------------
  # No order found — graceful success
  # ---------------------------------------------------------------------------

  test "no order with matching payment_intent_id returns success(:no_order_found)" do
    event = build_stripe_event("evt_pifail_notfound_001", "pi_test_nonexistent_999")

    result = Stripe::Handlers::PaymentIntentFailed.call(stripe_event: event)

    assert result.success?
    assert_equal :no_order_found, result.value
  end

  test "missing payment_intent_id in payload returns success(:no_order_found)" do
    event = StripeEvent.create!(
      stripe_event_id: "evt_pifail_no_pi_001",
      event_type: "payment_intent.payment_failed",
      status: "pending",
      payload: { id: "evt_pifail_no_pi_001", type: "payment_intent.payment_failed",
                 data: { object: { object: "payment_intent" } } }
    )

    result = Stripe::Handlers::PaymentIntentFailed.call(stripe_event: event)

    assert result.success?
    assert_equal :no_order_found, result.value
  end

  # ---------------------------------------------------------------------------
  # Idempotency — already payment_failed
  # ---------------------------------------------------------------------------

  test "already payment_failed order returns success(:already_handled)" do
    event = build_stripe_event("evt_pifail_already_001", @failed_order.stripe_payment_intent_id)

    result = Stripe::Handlers::PaymentIntentFailed.call(stripe_event: event)

    assert result.success?
    assert_equal :already_handled, result.value
    assert_equal "payment_failed", @failed_order.reload.status
  end

  private

  def build_stripe_event(event_id, payment_intent_id)
    StripeEvent.create!(
      stripe_event_id: event_id,
      event_type: "payment_intent.payment_failed",
      status: "pending",
      payload: {
        id: event_id,
        type: "payment_intent.payment_failed",
        data: {
          object: {
            id: payment_intent_id,
            object: "payment_intent",
            status: "requires_payment_method"
          }
        }
      }
    )
  end
end
