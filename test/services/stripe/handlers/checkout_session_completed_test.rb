# frozen_string_literal: true

require "test_helper"

# Tests for Stripe::Handlers::CheckoutSessionCompleted
#
# Responsibilities:
# - Finds order by Stripe session_id embedded in the event payload
# - Calls order.mark_paid! to transition from pending → paid
# - Associates the StripeEvent with the order (stripe_event.update! order:)
# - Returns success_result on successful transition
# - Returns success_result(:already_handled) if order is already paid (idempotency)
# - Returns failure_result if the order cannot be found
class Stripe::Handlers::CheckoutSessionCompletedTest < ActiveSupport::TestCase
  setup do
    @pending_order = orders(:b2c_pending)
    @pending_order.update_columns(stripe_session_id: "cs_test_pending_session_001")

    @paid_order = orders(:b2c_paid_with_stripe)

    @stripe_event = StripeEvent.create!(
      stripe_event_id: "evt_handler_cs_001",
      event_type: "checkout.session.completed",
      status: "pending",
      payload: checkout_payload("cs_test_pending_session_001")
    )
  end

  # ---------------------------------------------------------------------------
  # Happy path — pending order → mark_paid!
  # ---------------------------------------------------------------------------

  test "pending order is transitioned to paid status" do
    result = Stripe::Handlers::CheckoutSessionCompleted.call(
      stripe_event: @stripe_event
    )

    assert result.success?, "Expected success_result, got errors: #{result.errors.inspect}"
    assert_equal "paid", @pending_order.reload.status
  end

  test "stripe_event is associated with the order after handling" do
    Stripe::Handlers::CheckoutSessionCompleted.call(stripe_event: @stripe_event)

    assert_equal @pending_order.id, @stripe_event.reload.order_id
  end

  test "paid_at timestamp is set on the order after handling" do
    assert_nil @pending_order.paid_at

    Stripe::Handlers::CheckoutSessionCompleted.call(stripe_event: @stripe_event)

    assert_not_nil @pending_order.reload.paid_at
  end

  # ---------------------------------------------------------------------------
  # Idempotency — order already paid
  # ---------------------------------------------------------------------------

  test "already paid order returns success(:already_handled) without re-triggering transition" do
    already_paid_event = StripeEvent.create!(
      stripe_event_id: "evt_already_paid_001",
      event_type: "checkout.session.completed",
      status: "pending",
      payload: checkout_payload(@paid_order.stripe_session_id)
    )

    # Should not raise AASM::InvalidTransition
    assert_nothing_raised do
      result = Stripe::Handlers::CheckoutSessionCompleted.call(
        stripe_event: already_paid_event
      )

      assert result.success?
      assert_equal :already_handled, result.value
    end

    # Status must not have changed
    assert_equal "paid", @paid_order.reload.status
  end

  # ---------------------------------------------------------------------------
  # Order not found
  # ---------------------------------------------------------------------------

  test "unknown session_id returns failure_result" do
    event_with_unknown_session = StripeEvent.create!(
      stripe_event_id: "evt_unknown_session_001",
      event_type: "checkout.session.completed",
      status: "pending",
      payload: checkout_payload("cs_test_nonexistent_session_999")
    )

    result = Stripe::Handlers::CheckoutSessionCompleted.call(
      stripe_event: event_with_unknown_session
    )

    assert result.failure?
  end

  test "missing session_id in payload returns failure_result" do
    event_with_no_session = StripeEvent.create!(
      stripe_event_id: "evt_no_session_id_001",
      event_type: "checkout.session.completed",
      status: "pending",
      payload: { id: "evt_no_session_id_001", type: "checkout.session.completed",
                 data: { object: { object: "checkout.session" } } }
    )

    result = Stripe::Handlers::CheckoutSessionCompleted.call(
      stripe_event: event_with_no_session
    )

    assert result.failure?
  end

  private

  def checkout_payload(session_id)
    {
      id: "evt_cs_handler_payload",
      type: "checkout.session.completed",
      data: {
        object: {
          id: session_id,
          object: "checkout.session",
          payment_intent: "pi_test_intent_001",
          metadata: {}
        }
      }
    }
  end
end
