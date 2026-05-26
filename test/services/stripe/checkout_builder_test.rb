# frozen_string_literal: true

require "test_helper"

# Tests for Stripe::CheckoutBuilder service.
#
# Responsibilities:
# - Creates a Stripe Checkout Session via the Stripe API
# - Saves the resulting stripe_session_id on the order
# - Returns success_result with session URL on success
# - Returns failure_result without calling Stripe if order is not pending
# - Returns failure_result if the Stripe API call raises an error
class Stripe::CheckoutBuilderTest < ActiveSupport::TestCase
  setup do
    @b2c_pending_order = orders(:b2c_pending)
    @b2b_pending_order = orders(:b2b_pending_with_stripe)
    @paid_order        = orders(:b2c_paid_with_stripe)
  end

  # ---------------------------------------------------------------------------
  # Happy path — b2c standard tier (1900 cents)
  # ---------------------------------------------------------------------------

  test "b2c pending order creates Stripe session and saves stripe_session_id" do
    stub_stripe_checkout_session_create(
      session_id: "cs_test_new_b2c_001",
      url: "https://checkout.stripe.com/pay/cs_test_new_b2c_001"
    )

    result = Stripe::CheckoutBuilder.call(order: @b2c_pending_order)

    assert result.success?, "Expected success_result, got: #{result.errors.inspect}"
    assert_equal "https://checkout.stripe.com/pay/cs_test_new_b2c_001", result.value[:url]
    assert_equal "cs_test_new_b2c_001", @b2c_pending_order.reload.stripe_session_id
  end

  test "b2c pending order passes correct amount to Stripe (1900 cents)" do
    session_params_captured = nil

    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return do |request|
        session_params_captured = URI.decode_www_form(request.body).to_h
        {
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: stripe_session_response("cs_test_amount_check", "https://checkout.stripe.com/pay/cs_test_amount_check")
        }
      end

    Stripe::CheckoutBuilder.call(order: @b2c_pending_order)

    # Amount must match the order's price_cents
    assert_equal "1900", session_params_captured["line_items[0][price_data][unit_amount]"]
    assert_equal "eur", session_params_captured["line_items[0][price_data][currency]"]
  end

  # ---------------------------------------------------------------------------
  # Happy path — b2b starter tier (7900 cents)
  # ---------------------------------------------------------------------------

  test "b2b pending order creates Stripe session and saves stripe_session_id" do
    stub_stripe_checkout_session_create(
      session_id: "cs_test_new_b2b_001",
      url: "https://checkout.stripe.com/pay/cs_test_new_b2b_001"
    )

    result = Stripe::CheckoutBuilder.call(order: @b2b_pending_order)

    assert result.success?, "Expected success_result, got: #{result.errors.inspect}"
    assert_equal "cs_test_new_b2b_001", @b2b_pending_order.reload.stripe_session_id
  end

  test "b2b pending order passes correct amount to Stripe (7900 cents)" do
    session_params_captured = nil

    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return do |request|
        session_params_captured = URI.decode_www_form(request.body).to_h
        {
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: stripe_session_response("cs_test_b2b_amount_check", "https://checkout.stripe.com/pay/cs_test_b2b_amount_check")
        }
      end

    Stripe::CheckoutBuilder.call(order: @b2b_pending_order)

    assert_equal "7900", session_params_captured["line_items[0][price_data][unit_amount]"]
  end

  # ---------------------------------------------------------------------------
  # Failure — order not in pending status
  # ---------------------------------------------------------------------------

  test "order already paid returns failure_result without calling Stripe" do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_raise("Stripe should not be called for non-pending orders")

    result = Stripe::CheckoutBuilder.call(order: @paid_order)

    assert result.failure?, "Expected failure_result for non-pending order"
  end

  test "order in payment_failed status returns failure_result without calling Stripe" do
    failed_order = orders(:b2c_payment_failed)

    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_raise("Stripe should not be called for non-pending orders")

    result = Stripe::CheckoutBuilder.call(order: failed_order)

    assert result.failure?
  end

  # ---------------------------------------------------------------------------
  # Failure — Stripe API error
  # ---------------------------------------------------------------------------

  test "Stripe API error returns failure_result" do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(
        status: 402,
        headers: { "Content-Type" => "application/json" },
        body: { error: { type: "card_error", message: "Your card was declined." } }.to_json
      )

    result = Stripe::CheckoutBuilder.call(order: @b2c_pending_order)

    assert result.failure?
    assert_nil @b2c_pending_order.reload.stripe_session_id
  end

  test "Stripe network timeout returns failure_result" do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_raise(Stripe::APIConnectionError.new("Connection failed"))

    result = Stripe::CheckoutBuilder.call(order: @b2c_pending_order)

    assert result.failure?
  end

  private

  def stub_stripe_checkout_session_create(session_id:, url:)
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: stripe_session_response(session_id, url)
      )
  end

  def stripe_session_response(session_id, url)
    {
      id: session_id,
      object: "checkout.session",
      url: url,
      status: "open",
      payment_status: "unpaid",
      payment_intent: "pi_test_001",
      amount_total: 1900,
      currency: "eur"
    }.to_json
  end
end
