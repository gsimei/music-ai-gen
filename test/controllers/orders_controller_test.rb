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
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:customer_b2b)
  end

  # ---------------------------------------------------------------------------
  # GET /orders/new
  # ---------------------------------------------------------------------------

  test "GET /orders/new opens guided campaign without creating or paying an order" do
    host! "b2b.lvh.me"
    assert_no_difference "Order.count" do
      get new_order_path
    end
    assert_redirected_to new_campaign_path
  end

  # ---------------------------------------------------------------------------
  # GET /orders/wizard/1 — renders step 1 form
  # ---------------------------------------------------------------------------

  test "GET /orders/wizard/1 renders step 1 successfully" do
    host! "b2b.lvh.me"
    get wizard_order_path(step: 1)
    assert_response :success
  end

  test "GET /orders/wizard/1 renders step 1 on b2b host" do
    host! "b2b.lvh.me"
    get wizard_order_path(step: 1)
    assert_response :success
  end

  test "GET /orders/wizard/2 without step 1 data redirects back to step 1" do
    host! "b2b.lvh.me"
    # Session is empty — step 2 requires step 1 to have been completed first
    get wizard_order_path(step: 2)
    assert_redirected_to wizard_order_path(step: 1)
  end

  test "GET /orders/wizard/3 without prior step data redirects back to step 1" do
    host! "b2b.lvh.me"
    get wizard_order_path(step: 3)
    assert_redirected_to wizard_order_path(step: 1)
  end

  test "GET /orders/wizard/5 without prior step data redirects back to step 1" do
    host! "b2b.lvh.me"
    get wizard_order_path(step: 5)
    assert_redirected_to wizard_order_path(step: 1)
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/1 — valid params
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/1 with valid params redirects to step 2" do
    host! "b2b.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: { about: "Uma musica para o aniversario da minha mae" }
    }
    assert_redirected_to wizard_order_path(step: 2)
  end

  test "PATCH /orders/wizard/1 stores data in session" do
    host! "b2b.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: {
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

  test "PATCH /orders/wizard/1 without about re-renders step 1 with errors" do
    host! "b2b.lvh.me"
    patch wizard_order_path(step: 1), params: { order_wizard: { about: "" } }
    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/2 — valid params
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/2 with valid params redirects to step 3" do
    host! "b2b.lvh.me"
    # Pre-fill step 1 in session
    patch wizard_order_path(step: 1), params: {
      order_wizard: { about: "Uma musica" }
    }
    patch wizard_order_path(step: 2), params: {
      order_wizard: {
        music_style: "pop",
        language: "it"
      }
    }
    assert_redirected_to wizard_order_path(step: 3)
  end

  test "PATCH /orders/wizard/2 without music_style re-renders step 2 with errors" do
    host! "b2b.lvh.me"
    patch wizard_order_path(step: 1), params: {
      order_wizard: { about: "Uma musica" }
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
    host! "b2b.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_3(host: "b2b.lvh.me")
    patch wizard_order_path(step: 4), params: {
      order_wizard: { voice_id: voice.id }
    }
    assert_redirected_to wizard_order_path(step: 5)
  end

  test "PATCH /orders/wizard/4 with inactive voice re-renders step 4 with errors" do
    host! "b2b.lvh.me"
    voice = voices(:inactive_voice)
    fill_steps_1_to_3(host: "b2b.lvh.me")
    patch wizard_order_path(step: 4), params: {
      order_wizard: { voice_id: voice.id }
    }
    assert_response :unprocessable_entity
  end


  # ---------------------------------------------------------------------------
  # PATCH /orders/wizard/5 — final step, creates Order + Briefing
  # ---------------------------------------------------------------------------

  test "PATCH /orders/wizard/5 with complete valid data creates order and redirects" do
    host! "b2b.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: voice)

    assert_difference "Order.count", 1 do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "starter" }
      }
    end
    # Should redirect to the new order (e.g., order path or payment path)
    assert_response :redirect
  end

  test "PATCH /orders/wizard/5 creates an associated briefing" do
    host! "b2b.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: voice)

    assert_difference "Briefing.count", 1 do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "starter" }
      }
    end
  end

  test "PATCH /orders/wizard/5 with invalid tier re-renders step 5 with errors" do
    host! "b2b.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: voice)

    assert_no_difference "Order.count" do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "standard" }  # standard does not exist for b2b
      }
    end
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/5 with pro-only voice and starter tier re-renders with errors" do
    host! "b2b.lvh.me"
    pro_voice = voices(:pro_voice)  # min_tier: 1
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: pro_voice)

    assert_no_difference "Order.count" do
      patch wizard_order_path(step: 5), params: {
        order_wizard: { tier: "starter" }  # starter maps to min_tier=0, pro_voice needs min_tier=1
      }
    end
    assert_response :unprocessable_entity
  end

  test "PATCH /orders/wizard/5 with pro voice and pro tier succeeds" do
    host! "b2b.lvh.me"
    pro_voice = voices(:pro_voice)
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: pro_voice)

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
    host! "b2b.lvh.me"
    voice = voices(:standard_voice)
    fill_steps_1_to_4(host: "b2b.lvh.me", voice: voice)
    patch wizard_order_path(step: 5), params: {
      order_wizard: { tier: "starter" }
    }
    assert_response :redirect

    # After clearing, step 2 should no longer be accessible
    get wizard_order_path(step: 2)
    assert_redirected_to wizard_order_path(step: 1)
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/checkout — initiates Stripe Checkout
  # ---------------------------------------------------------------------------

  # Checkout creates a payment session; only the webhook confirms payment.
  test "POST /orders/:id/checkout for pending order opens Stripe without marking paid" do
    host! "b2b.lvh.me"
    order = orders(:b2b_pending)
    Stripe::CheckoutBuilder.stub(:call, ServiceResult.new(success: true, value: { url: "https://checkout.stripe.com/test" }, errors: nil)) do
      post checkout_order_path(order)
    end
    assert_equal "pending", order.reload.status
    assert_redirected_to "https://checkout.stripe.com/test"
  end

  test "POST /orders/:id/checkout for already-paid order redirects to chat without re-transitioning" do
    host! "b2b.lvh.me"
    order = orders(:b2b_paid_with_stripe)
    post checkout_order_path(order)
    assert_redirected_to order_path(order)
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/approve_lyrics (new single-page flow action)
  # ---------------------------------------------------------------------------

  test "POST approve_lyrics on order: unauthenticated user is redirected to sign in" do
    sign_out :user
    host! "b2b.lvh.me"
    order = orders(:b2b_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_lyrics_order_path(order), params: { draft_id: draft.id }

    assert_redirected_to new_user_session_path
  end

  test "POST approve_lyrics on order: success redirects to order_path" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_lyrics_order_path(order), params: { draft_id: draft.id }

    assert_redirected_to order_path(order)
  end

  test "POST approve_lyrics on order: transitions order to lyrics_approved" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_lyrics_ready)
    draft = lyrics_drafts(:draft_lyrics_ready_v1)

    post approve_lyrics_order_path(order), params: { draft_id: draft.id }

    assert_equal "lyrics_approved", order.reload.status
  end

  test "POST approve_lyrics on order: missing draft_id returns error response" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_lyrics_ready)

    post approve_lyrics_order_path(order), params: { draft_id: nil }

    assert_response :redirect
    assert_not_equal "lyrics_approved", order.reload.status
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/regenerate_lyrics (new single-page flow action)
  # ---------------------------------------------------------------------------

  test "POST regenerate_lyrics on order: unauthenticated user is redirected to sign in" do
    sign_out :user
    host! "b2b.lvh.me"
    order = orders(:b2b_lyrics_ready)

    post regenerate_lyrics_order_path(order),
         params:  { user_feedback: "More romantic" },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_redirected_to new_user_session_path
  end

  test "POST regenerate_lyrics on order: success enqueues GenerateLyricsJob" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_lyrics_ready)

    assert_enqueued_with(job: GenerateLyricsJob) do
      post regenerate_lyrics_order_path(order),
           params:  { user_feedback: "More romantic" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  test "POST regenerate_lyrics on order: regen limit reached returns error turbo stream" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_lyrics_ready_at_limit)

    assert_no_enqueued_jobs only: GenerateLyricsJob do
      post regenerate_lyrics_order_path(order),
           params:  { user_feedback: "ancora" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_includes response.content_type, "turbo-stream"
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/approve_music (new single-page flow action)
  # ---------------------------------------------------------------------------

  test "POST approve_music on order: unauthenticated user is redirected to sign in" do
    sign_out :user
    host! "b2b.lvh.me"
    order = orders(:b2b_preview_ready)

    post approve_music_order_path(order), params: { variant: "a" }

    assert_redirected_to new_user_session_path
  end

  test "POST approve_music on order: success transitions order to approved" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_music_order_path(order), params: { variant: "a" }

    assert_equal "approved", order.reload.status
  end

  test "POST approve_music on order: invalid variant returns error" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post approve_music_order_path(order), params: { variant: "z" }

    assert_not_equal "approved", order.reload.status
    assert_response :redirect
  end

  # ---------------------------------------------------------------------------
  # POST /orders/:id/regenerate_music (new single-page flow action)
  # ---------------------------------------------------------------------------

  test "POST regenerate_music on order: unauthenticated user is redirected to sign in" do
    sign_out :user
    host! "b2b.lvh.me"
    order = orders(:b2b_preview_ready)

    post regenerate_music_order_path(order), params: { melody_hint: "More drums" }

    assert_redirected_to new_user_session_path
  end

  test "POST regenerate_music on order: success transitions order to music_generating" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    post regenerate_music_order_path(order), params: { melody_hint: "More drums" }

    assert_equal "music_generating", order.reload.status
  end

  test "POST regenerate_music on order: success enqueues GenerateMusicJob" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready)

    assert_enqueued_with(job: GenerateMusicJob, args: [order.id]) do
      post regenerate_music_order_path(order), params: { melody_hint: "More drums" }
    end
  end

  test "POST regenerate_music on order: regen limit reached returns error" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_preview_ready_at_limit)

    assert_no_enqueued_jobs only: GenerateMusicJob do
      post regenerate_music_order_path(order), params: { melody_hint: "More drums" }
    end
    assert_response :redirect
  end

  test "POST regenerate_music on order: invalid state (not preview_ready) returns error" do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    order = orders(:b2b_approved)

    assert_no_enqueued_jobs only: GenerateMusicJob do
      post regenerate_music_order_path(order), params: { melody_hint: "More drums" }
    end
    assert_response :redirect
  end

  private

  # Fills steps 1-3 in the session using PATCH requests.
  def fill_steps_1_to_3(host:)
    host! host
    patch wizard_order_path(step: 1), params: {
      order_wizard: { about: "Uma musica para presente" }
    }
    patch wizard_order_path(step: 2), params: {
      order_wizard: { music_style: "pop", language: "it" }
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
