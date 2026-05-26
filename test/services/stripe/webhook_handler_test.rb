# frozen_string_literal: true

require "test_helper"

# Tests for Stripe::WebhookHandler service.
#
# Responsibilities:
# - Verifies HMAC-SHA256 signature from Stripe
# - Idempotency gate: already-processed events return success without re-enqueuing
# - Unknown/unhandled event types are stored with status "skipped", no job enqueued
# - Valid new handled events: create StripeEvent (status: pending), enqueue
#   StripeWebhookProcessorJob, return success_result(:enqueued)
# - Invalid signature: return failure_result("invalid_signature"), no DB writes
class Stripe::WebhookHandlerTest < ActiveSupport::TestCase
  WEBHOOK_SECRET = "whsec_test_secret_for_tests"

  HANDLED_EVENT_TYPES = %w[
    checkout.session.completed
    payment_intent.payment_failed
    charge.refunded
  ].freeze

  setup do
    ENV["STRIPE_WEBHOOK_SECRET"] = WEBHOOK_SECRET
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  # ---------------------------------------------------------------------------
  # Valid signature — new handled event → StripeEvent created, job enqueued
  # ---------------------------------------------------------------------------

  test "valid signature with new checkout.session.completed event creates StripeEvent and enqueues job" do
    payload   = checkout_session_payload("evt_new_checkout_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    assert_difference "StripeEvent.count", 1 do
      assert_enqueued_with(job: StripeWebhookProcessorJob) do
        result = Stripe::WebhookHandler.call(
          payload: payload,
          signature_header: "t=#{timestamp},v1=#{signature}"
        )

        assert result.success?
        assert_equal :enqueued, result.value
      end
    end

    event = StripeEvent.find_by!(stripe_event_id: "evt_new_checkout_001")
    assert_equal "pending", event.status
    assert_equal "checkout.session.completed", event.event_type
  end

  test "valid signature with new payment_intent.payment_failed event creates StripeEvent and enqueues job" do
    payload   = payment_intent_failed_payload("evt_new_pifailed_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    assert_difference "StripeEvent.count", 1 do
      assert_enqueued_with(job: StripeWebhookProcessorJob) do
        result = Stripe::WebhookHandler.call(
          payload: payload,
          signature_header: "t=#{timestamp},v1=#{signature}"
        )
        assert result.success?
        assert_equal :enqueued, result.value
      end
    end
  end

  test "valid signature with new charge.refunded event creates StripeEvent and enqueues job" do
    payload   = charge_refunded_payload("evt_new_refund_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    assert_difference "StripeEvent.count", 1 do
      assert_enqueued_with(job: StripeWebhookProcessorJob) do
        result = Stripe::WebhookHandler.call(
          payload: payload,
          signature_header: "t=#{timestamp},v1=#{signature}"
        )
        assert result.success?
        assert_equal :enqueued, result.value
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Idempotency — already-processed event
  # ---------------------------------------------------------------------------

  test "already processed event returns success(:already_processed) without creating new StripeEvent" do
    existing_event = stripe_events(:checkout_completed)
    assert existing_event.processed?, "Fixture must be in processed status"

    payload   = build_payload(existing_event.stripe_event_id, existing_event.event_type)
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    assert_no_difference "StripeEvent.count" do
      assert_no_enqueued_jobs(only: StripeWebhookProcessorJob) do
        result = Stripe::WebhookHandler.call(
          payload: payload,
          signature_header: "t=#{timestamp},v1=#{signature}"
        )

        assert result.success?
        assert_equal :already_processed, result.value
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Unhandled event type — stored as skipped, no job
  # ---------------------------------------------------------------------------

  test "unhandled event type customer.updated creates StripeEvent with status skipped and no job" do
    payload   = build_payload("evt_unhandled_new_001", "customer.updated")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    assert_difference "StripeEvent.count", 1 do
      assert_no_enqueued_jobs(only: StripeWebhookProcessorJob) do
        result = Stripe::WebhookHandler.call(
          payload: payload,
          signature_header: "t=#{timestamp},v1=#{signature}"
        )

        assert result.success?
      end
    end

    event = StripeEvent.find_by!(stripe_event_id: "evt_unhandled_new_001")
    assert_equal "skipped", event.status
  end

  # ---------------------------------------------------------------------------
  # Invalid signature → failure_result, no side effects
  # ---------------------------------------------------------------------------

  test "invalid HMAC signature returns failure_result without creating StripeEvent" do
    payload = checkout_session_payload("evt_invalid_sig_001")

    assert_no_difference "StripeEvent.count" do
      assert_no_enqueued_jobs(only: StripeWebhookProcessorJob) do
        result = Stripe::WebhookHandler.call(
          payload: payload,
          signature_header: "t=#{Time.now.to_i},v1=bad_signature_here"
        )

        assert result.failure?
        assert_equal "invalid_signature", result.errors
      end
    end
  end

  test "missing signature header returns failure_result" do
    payload = checkout_session_payload("evt_no_sig_001")

    result = Stripe::WebhookHandler.call(
      payload: payload,
      signature_header: nil
    )

    assert result.failure?
  end

  test "malformed signature header returns failure_result" do
    payload = checkout_session_payload("evt_malformed_sig_001")

    result = Stripe::WebhookHandler.call(
      payload: payload,
      signature_header: "not_a_valid_stripe_signature"
    )

    assert result.failure?
  end

  private

  def compute_stripe_signature(timestamp, payload)
    OpenSSL::HMAC.hexdigest("SHA256", WEBHOOK_SECRET, "#{timestamp}.#{payload}")
  end

  def checkout_session_payload(event_id)
    {
      id: event_id,
      type: "checkout.session.completed",
      data: {
        object: {
          id: "cs_test_session_001",
          object: "checkout.session",
          payment_intent: "pi_test_001",
          metadata: {}
        }
      }
    }.to_json
  end

  def payment_intent_failed_payload(event_id)
    {
      id: event_id,
      type: "payment_intent.payment_failed",
      data: {
        object: {
          id: "pi_test_failed_001",
          object: "payment_intent"
        }
      }
    }.to_json
  end

  def charge_refunded_payload(event_id)
    {
      id: event_id,
      type: "charge.refunded",
      data: {
        object: {
          id: "ch_test_refund_001",
          object: "charge",
          payment_intent: "pi_test_001",
          amount: 1900,
          amount_refunded: 1900
        }
      }
    }.to_json
  end

  def build_payload(event_id, event_type)
    {
      id: event_id,
      type: event_type,
      data: { object: {} }
    }.to_json
  end
end
