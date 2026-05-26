# frozen_string_literal: true

require "test_helper"

# Integration tests for OrdersController — the wizard that guides a visitor
# through 5 steps to create an Order + Briefing.
#
# Routes expected (added inside brand constraints):
#   GET  /orders/new            -> orders#new
#   GET  /orders/wizard/:step   -> orders#wizard_show
#   PATCH /orders/wizard/:step  -> orders#wizard_update
#
# Brand detection is based on HTTP host. Tests use host! to simulate b2b/b2c.
# b2c host used: "b2c.lvh.me"  (defined in BRANDS_CONFIG)
# b2b host used: "b2b.lvh.me"  (defined in BRANDS_CONFIG)
class OrdersControllerTest < ActionDispatch::IntegrationTest
  # ---------------------------------------------------------------------------
  # GET /orders/new
  # ---------------------------------------------------------------------------

  test "GET /orders/new redirects to step 1" do
    host! "b2c.lvh.me"
    get new_order_path
    assert_redirected_to wizard_order_path(step: 1)
  end

  test "GET /orders/new redirects to step 1 on b2b host" do
    host! "b2b.lvh.me"
    get new_order_path
    assert_redirected_to wizard_order_path(step: 1)
  end

  # ---------------------------------------------------------------------------
  # GET /orders/wizard/1 — renders step 1 form
  # ---------------------------------------------------------------------------

  test "GET /orders/wizard/1 renders step 1 successfully" do
    host! "b2c.lvh.me"
    get wizard_order_path(step: 1)
    assert_response :success
  end

  test "GET /orders/wizard/1 renders step 1 on b2b host" do
    host! "b2b.lvh.me"
    get wizard_order_path(step: 1)
    assert_response :success
  end

  test "GET /orders/wizard/2 without step 1 data redirects back to step 1" do
    host! "b2c.lvh.me"
    # Session is empty — step 2 requires step 1 to have been completed first
    get wizard_order_path(step: 2)
    assert_redirected_to wizard_order_path(step: 1)
  end

  test "GET /orders/wizard/3 without prior step data redirects back to step 1" do
    host! "b2c.lvh.me"
    get wizard_order_path(step: 3)
    assert_redirected_to wizard_order_path(step: 1)
  end

  test "GET /orders/wizard/5 without prior step data redirects back to step 1" do
    host! "b2c.lvh.me"
    get wizard_order_path(step: 5)
    assert_redirected_to wizard_order_path(step: 1)
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/1 — valid params
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/1 with valid params redirects to step 2" do
    host! "b2c.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "customer@example.com",
        about: "Uma musica para o aniversario da minha mae"
      }
    }
    assert_redirected_to wizard_order_path(step: 2)
  end

  test "PATCH /orders/wizard/1 stores data in session" do
    host! "b2c.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "customer@example.com",
        about: "Uma musica para o aniversario",
        recipient: "Maria",
        occasion: "birthday"
      }
    }
    assert_redirected_to wizard_order_path(step: 2)
    # After storing step 1 data, step 2 should be accessible
    get wizard_order_path(step: 2)
    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/1 — invalid params
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/1 without delivery_email re-renders step 1 with errors" do
    host! "b2c.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        about: "Uma musica para o aniversario"
      }
    }
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/1 without about re-renders step 1 with errors" do
    host! "b2c.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "customer@example.com"
      }
    }
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/1 with malformed email re-renders step 1" do
    host! "b2c.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "not-an-email",
        about: "Uma musica"
      }
    }
    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/2 — valid params
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/2 with valid params redirects to step 3" do
    host! "b2c.lvh.me"
    # Pre-fill step 1 in session
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "customer@example.com",
        about: "Uma musica"
      }
    }
    patch wizard_order_path(step: 2), params: {
      order_wizard: {
        music_style: "pop"
      }
    }
    assert_redirected_to wizard_order_path(step: 3)
  end

  test "PATCH /orders/wizard/2 without music_style re-renders step 2 with errors" do
    host! "b2c.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "customer@example.com",
        about: "Uma musica"
      }
    }
    patch wizard_order_path(step: 2), params: {
      order_wizard: {
        mood: "happy"
      }
    }
    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/4 — voice validation
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/4 with valid active voice for brand redirects to step 5" do
    host! "b2c.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_3(host: "b2c.lvh.me")
    patch wizard_order_path(step: 4), params: {
      order_wizard: { voice_id: voice.id }
    }
    assert_redirected_to wizard_order_path(step: 5)
  end

  test "PATCH /orders/wizard/4 with inactive voice re-renders step 4 with errors" do
    host! "b2c.lvh.me"
    voice = voices(:inactive_voice)
    fill_steps_1_to_3(host: "b2c.lvh.me")
    patch wizard_order_path(step: 4), params: {
      order_wizard: { voice_id: voice.id }
    }
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/4 with voice not allowed for brand re-renders step 4 with errors" do
    host! "b2c.lvh.me"
    voice = voices(:b2b_only_voice)  # not allowed for b2c
    fill_steps_1_to_3(host: "b2c.lvh.me")
    patch wizard_order_path(step: 4), params: {
      order_wizard: { voice_id: voice.id }
    }
    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/5 — final step, creates Order + Briefing
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/5 with complete valid data creates order and redirects" do
    host! "b2c.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: voice)

    assert_difference "Order.count", 1 do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "standard" }
      }
    end
    # Should redirect to the new order (e.g., order path or payment path)
    assert_response :redirect
  end

  test "PATCH /orders/wizard/5 creates an associated briefing" do
    host! "b2c.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: voice)

    assert_difference "Briefing.count", 1 do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "standard" }
      }
    end
  end

  test "PATCH /orders/wizard/5 with invalid tier re-renders step 5 with errors" do
    host! "b2c.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: voice)

    assert_no_difference "Order.count" do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "starter" }  # b2b tier, invalid for b2c
      }
    end
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/5 with pro-only voice and standard tier re-renders with errors" do
    host! "b2c.lvh.me"
    pro_voice = voices(:pro_voice)  # min_tier: 1
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: pro_voice)

    assert_no_difference "Order.count" do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "standard" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/5 with pro voice and pro tier succeeds for b2c" do
    host! "b2c.lvh.me"
    pro_voice = voices(:pro_voice)
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: pro_voice)

    assert_difference "Order.count", 1 do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "pro" }
      }
    end
    assert_response :redirect
  end

  # ---------------------------------------------------------------------------
  # Brand assignment on created order
  # ---------------------------------------------------------------------------

  test "order created via b2c host has brand b2c" do
    host! "b2c.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: voice)
    patch wizard_order_path(step: 5), params: {
      order_wizard: { tier: "standard" }
    }
    assert_response :redirect
    order = Order.order(created_at: :desc).first
    assert_equal "b2c", order.brand
  end

  test "order created via b2b host has brand b2b" do
    host! "b2b.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: voice)
    patch wizard_order_path(step: 5), params: {
      order_wizard: { tier: "starter" }
    }
    assert_response :redirect
    order = Order.order(created_at: :desc).first
    assert_equal "b2b", order.brand
  end

  # ---------------------------------------------------------------------------
  # Session is cleared after successful order creation
  # ---------------------------------------------------------------------------

  test "wizard session is cleared after successful order creation" do
    host! "b2c.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2c.lvh.me", voice: voice)
    patch wizard_order_path(step: 5), params: {
      order_wizard: { tier: "standard" }
    }
    assert_response :redirect

    # After clearing, step 2 should no longer be accessible
    get wizard_order_path(step: 2)
    assert_redirected_to wizard_order_path(step: 1)
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/checkout — initiates Stripe Checkout
  # ---------------------------------------------------------------------------

  test "POST /orders/:id/checkout for pending order redirects to Stripe checkout URL" do
    host! "b2c.lvh.me"
    order = orders(:b2c_pending)
    checkout_url = "https://checkout.stripe.com/pay/cs_test_controller_001"

    # Stub CheckoutBuilder to return a success result with the URL
    Stripe::CheckoutBuilder.stub(:call, ->(_args) {
      ServiceResult.new(success: true, value: { url: checkout_url }, errors: nil)
    }) do
      post checkout_order_path(order)
    end

    assert_redirected_to checkout_url
  end

  test "POST /orders/:id/checkout for non-pending order redirects to order path" do
    host! "b2c.lvh.me"
    order = orders(:b2c_paid_with_stripe)

    # CheckoutBuilder should NOT be called for non-pending orders
    Stripe::CheckoutBuilder.stub(:call, ->(_args) { raise "Should not call CheckoutBuilder for paid order" }) do
      post checkout_order_path(order)
    end

    assert_redirected_to order_path(order)
  end

  test "POST /orders/:id/checkout when CheckoutBuilder fails redirects to order path with alert" do
    host! "b2c.lvh.me"
    order = orders(:b2c_pending)

    Stripe::CheckoutBuilder.stub(:call, ->(_args) {
      ServiceResult.new(success: false, value: nil, errors: "stripe_error")
    }) do
      post checkout_order_path(order)
    end

    assert_redirected_to order_path(order)
  end

  private

  # Fills steps 1-3 in the session using PATCH requests.
  def fill_steps_1_to_3(host:)
    host! host
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
        delivery_email: "customer@example.com",
        about: "Uma musica para presente"
      }
    }
    patch wizard_order_path(step: 2), params: {
      order_wizard: { music_style: "pop" }
    }
    patch wizard_order_path(step: 3), params: {
      order_wizard: { keywords: "love" }
    }
  end

  # Fills steps 1-4 in the session using PATCH requests.
  def fill_steps_1_to_4(host:, voice:)
    fill_steps_1_to_3(host: host)
    host! host
    patch wizard_order_path(step: 4), params: {
      order_wizard: { voice_id: voice.id }
    }
  end
end
