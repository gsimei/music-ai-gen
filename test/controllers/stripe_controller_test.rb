# frozen_string_literal: true

require "test_helper"

# Integration tests for StripeController#webhook
#
# Route: POST /stripe/webhook
# - Outside BrandConstraint (no brand/locale detection)
# - Skips set_brand_and_locale before_action
# - Returns 200 for valid HMAC signature (always, even if processing is async)
# - Returns 400 for invalid HMAC signature
#
# Per Stripe best practices: always return 200 for valid signature and
# handle processing asynchronously — never return 5xx.
class StripeControllerTest < ActionDispatch::IntegrationTest
  WEBHOOK_SECRET = "whsec_test_secret_for_tests"

  setup do
    ENV["STRIPE_WEBHOOK_SECRET"] = WEBHOOK_SECRET
  end

  teardown do
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  # ---------------------------------------------------------------------------
  # Valid HMAC → 200
  # ---------------------------------------------------------------------------

  test "POST /stripe/webhook with valid HMAC returns 200" do
    payload   = checkout_session_payload("evt_controller_valid_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    post stripe_webhook_path,
         params: payload,
         headers: {
           "Content-Type"    => "application/json",
           "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
         }

    assert_response :ok
  end

  test "POST /stripe/webhook with valid HMAC enqueues StripeWebhookProcessorJob" do
    payload   = checkout_session_payload("evt_controller_enqueue_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    assert_enqueued_with(job: StripeWebhookProcessorJob) do
      post stripe_webhook_path,
           params: payload,
           headers: {
             "Content-Type"    => "application/json",
             "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
           }
    end
  end

  test "POST /stripe/webhook with valid HMAC for payment_failed event returns 200" do
    payload   = payment_intent_failed_payload("evt_controller_pifail_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    post stripe_webhook_path,
         params: payload,
         headers: {
           "Content-Type"    => "application/json",
           "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
         }

    assert_response :ok
  end

  # ---------------------------------------------------------------------------
  # Invalid HMAC → 400
  # ---------------------------------------------------------------------------

  test "POST /stripe/webhook with invalid HMAC returns 400" do
    payload = checkout_session_payload("evt_controller_bad_sig_001")

    post stripe_webhook_path,
         params: payload,
         headers: {
           "Content-Type"    => "application/json",
           "Stripe-Signature" => "t=#{Time.now.to_i},v1=totallywrongsignature"
         }

    assert_response :bad_request
  end

  test "POST /stripe/webhook with missing Stripe-Signature header returns 400" do
    payload = checkout_session_payload("evt_controller_no_sig_001")

    post stripe_webhook_path,
         params: payload,
         headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
  end

  test "POST /stripe/webhook with invalid HMAC does not create StripeEvent" do
    payload = checkout_session_payload("evt_controller_no_create_001")

    assert_no_difference "StripeEvent.count" do
      post stripe_webhook_path,
           params: payload,
           headers: {
             "Content-Type"    => "application/json",
             "Stripe-Signature" => "t=#{Time.now.to_i},v1=badsignature"
           }
    end
  end

  # ---------------------------------------------------------------------------
  # Route is outside BrandConstraint — accessible from any host
  # ---------------------------------------------------------------------------

  test "POST /stripe/webhook is accessible without brand host constraint" do
    payload   = checkout_session_payload("evt_controller_nohost_001")
    timestamp = Time.now.to_i
    signature = compute_stripe_signature(timestamp, payload)

    # Use a generic host — not b2b.lvh.me or b2c.lvh.me
    host! "localhost"

    post stripe_webhook_path,
         params: payload,
         headers: {
           "Content-Type"    => "application/json",
           "Stripe-Signature" => "t=#{timestamp},v1=#{signature}"
         }

    assert_response :ok
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
          id: "cs_test_ctrl_session_001",
          object: "checkout.session",
          payment_intent: "pi_test_ctrl_001",
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
          id: "pi_test_ctrl_failed_001",
          object: "payment_intent"
        }
      }
    }.to_json
  end
end
