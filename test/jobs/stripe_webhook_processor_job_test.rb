# frozen_string_literal: true

require "test_helper"

# Tests for StripeWebhookProcessorJob
#
# Responsibilities:
# - Dispatches to the correct Stripe handler based on event_type
# - Marks the StripeEvent as processed (status: "processed") on success
# - Returns early without calling any handler if event is already processed
# - Raises an error (for Solid Queue retry) when the handler returns failure_result
class StripeWebhookProcessorJobTest < ActiveJob::TestCase
  # ---------------------------------------------------------------------------
  # checkout.session.completed → Stripe::Handlers::CheckoutSessionCompleted
  # ---------------------------------------------------------------------------

  test "checkout.session.completed dispatches to CheckoutSessionCompleted handler" do
    event = stripe_events(:checkout_completed)
    # Reset to pending so the job will process it
    event.update_columns(status: "pending", processed_at: nil)

    # The handler is called with the stripe_event
    Stripe::Handlers::CheckoutSessionCompleted.stub(:call, ->(_args) { ServiceResult.new(success: true, value: nil, errors: nil) }) do
      StripeWebhookProcessorJob.perform_now(event.id)
    end

    assert_equal "processed", event.reload.status
    assert_not_nil event.reload.processed_at
  end

  test "checkout.session.completed marks event processed after handler succeeds" do
    event = stripe_events(:checkout_completed)
    event.update_columns(status: "pending", processed_at: nil)

    Stripe::Handlers::CheckoutSessionCompleted.stub(:call, ->(_args) { ServiceResult.new(success: true, value: nil, errors: nil) }) do
      StripeWebhookProcessorJob.perform_now(event.id)
    end

    assert_equal "processed", event.reload.status
  end

  # ---------------------------------------------------------------------------
  # payment_intent.payment_failed → Stripe::Handlers::PaymentIntentFailed
  # ---------------------------------------------------------------------------

  test "payment_intent.payment_failed dispatches to PaymentIntentFailed handler" do
    event = stripe_events(:payment_failed_event)
    assert_equal "payment_intent.payment_failed", event.event_type

    Stripe::Handlers::PaymentIntentFailed.stub(:call, ->(_args) { ServiceResult.new(success: true, value: nil, errors: nil) }) do
      StripeWebhookProcessorJob.perform_now(event.id)
    end

    assert_equal "processed", event.reload.status
  end

  # ---------------------------------------------------------------------------
  # charge.refunded → Stripe::Handlers::ChargeRefunded
  # ---------------------------------------------------------------------------

  test "charge.refunded dispatches to ChargeRefunded handler" do
    event = stripe_events(:charge_refunded_event)
    assert_equal "charge.refunded", event.event_type

    Stripe::Handlers::ChargeRefunded.stub(:call, ->(_args) { ServiceResult.new(success: true, value: nil, errors: nil) }) do
      StripeWebhookProcessorJob.perform_now(event.id)
    end

    assert_equal "processed", event.reload.status
  end

  # ---------------------------------------------------------------------------
  # Already processed event — early return, no handler called
  # ---------------------------------------------------------------------------

  test "already processed event returns early without calling any handler" do
    event = stripe_events(:checkout_completed)
    assert_equal "processed", event.status

    handler_called = false

    Stripe::Handlers::CheckoutSessionCompleted.stub(:call, ->(_args) { handler_called = true; ServiceResult.new(success: true, value: nil, errors: nil) }) do
      StripeWebhookProcessorJob.perform_now(event.id)
    end

    assert_not handler_called, "Handler should not be called for already-processed events"
  end

  # ---------------------------------------------------------------------------
  # Handler failure → raise (triggers Solid Queue retry)
  # ---------------------------------------------------------------------------

  test "handler returning failure_result raises an error for retry" do
    event = stripe_events(:payment_failed_event)

    failure = ServiceResult.new(success: false, value: nil, errors: "handler_error")

    assert_raises(RuntimeError) do
      Stripe::Handlers::PaymentIntentFailed.stub(:call, ->(_args) { failure }) do
        StripeWebhookProcessorJob.perform_now(event.id)
      end
    end
  end

  test "event status is not set to processed when handler raises" do
    event = stripe_events(:charge_refunded_event)

    assert_raises(RuntimeError) do
      Stripe::Handlers::ChargeRefunded.stub(:call, ->(_args) { raise "unexpected error" }) do
        StripeWebhookProcessorJob.perform_now(event.id)
      end
    end

    assert_not_equal "processed", event.reload.status
  end

  # ---------------------------------------------------------------------------
  # Unhandled event_type — the job should not be enqueued for these; if it is,
  # raise so we know something routed incorrectly
  # ---------------------------------------------------------------------------

  test "unhandled event_type raises error rather than silently skipping" do
    # skipped_event has event_type: "customer.updated" — the job should never
    # be called for this, but if it is, the job must raise to surface the bug
    event = stripe_events(:skipped_event)
    # Reset to pending to simulate wrong routing
    event.update_columns(status: "pending")

    assert_raises(StandardError) do
      StripeWebhookProcessorJob.perform_now(event.id)
    end
  end
end
