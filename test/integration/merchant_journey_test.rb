require "test_helper"

class MerchantJourneyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  setup { host! "b2b.lvh.me" }

  test "new merchant reaches signup directly and returns to guided campaign" do
    get new_order_path
    assert_redirected_to new_user_registration_path
    follow_redirect!
    assert_select 'input[name="user[email]"]'
    assert_difference "User.count", 1 do
      post user_registration_path, params: { user: { email: "journey@example.test", password: "Test-Campaign-123!", password_confirmation: "Test-Campaign-123!" } }
    end
    assert_redirected_to new_campaign_path
    follow_redirect!
    assert_select "form.campaign-builder"
  end

  test "return from paid checkout immediately resumes creation and cannot be forged" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_pending)
    order.update!(currency: "BRL", stripe_session_id: "cs_return_test")
    campaign = Campaign.create!(order: order, business_name: "Pizzaria", offer: "Oferta de terça", contact: "@teste", style: "animado", call_to_action: "Saiba mais no Instagram")
    unpaid = Stripe::Checkout::Session.construct_from(id: "cs_return_test", payment_status: "unpaid", amount_total: 7900, currency: "brl")
    Stripe::Checkout::Session.stub(:retrieve, unpaid) do
      get campaign_path(campaign), params: { payment: "processing", status: "paid", session_id: "cs_other" }
      assert_response :success
      assert order.reload.pending?
      assert_select "[role=status]", text: /Aguardando/
      assert_select "form.campaign-builder", count: 0
      assert_select 'input[type="submit"]', count: 0
    end
    paid = Stripe::Checkout::Session.construct_from(id: "cs_return_test", payment_status: "paid", amount_total: 7900, currency: "brl", payment_intent: "pi_test")
    Stripe::Checkout::Session.stub(:retrieve, paid) do
      assert_enqueued_jobs 1, only: GenerateLyricsJob do
        get campaign_path(campaign), params: { payment: "processing" }
      end
      assert_redirected_to order_chat_path(order_id: order.id)
    end
  end

  test "creation progress recovers missed updates and is scoped to the merchant" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_pending)
    order.update!(status: "paid")
    get order_chat_status_path(order_id: order.id), params: { version: order.creation_version }
    assert_response :no_content
    get order_chat_status_path(order_id: order.id), params: { version: "old" }
    assert_response :success
    assert_equal order.creation_version, response.headers["X-Creation-Version"]
    assert_includes response.body, 'target="chat-workflow"'
    sign_out :user
    sign_in users(:customer_other)
    get order_chat_status_path(order_id: order.id)
    assert_response :not_found
  end

  test "video progress replaces delivery after a missed update" do
    sign_in users(:customer_b2b)
    order = orders(:b2b_pending)
    order.update!(status: "approved")
    campaign = Campaign.create!(order: order, business_name: "Pizzaria", offer: "Oferta de terça", contact: "@teste", style: "animado", call_to_action: "Saiba mais no Instagram", video_status: "rendering")
    get status_campaign_path(campaign), params: { version: "rendering" }
    assert_response :no_content
    campaign.update!(video_status: "failed", video_error: "Tente novamente.")
    get status_campaign_path(campaign), params: { version: "rendering" }
    assert_response :success
    assert_equal "failed", response.headers["X-Creation-Version"]
    assert_includes response.body, 'target="campaign-delivery"'
    assert_includes response.body, "Tentar montar o vídeo novamente"
  end
end
