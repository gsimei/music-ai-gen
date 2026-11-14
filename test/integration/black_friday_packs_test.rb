require "test_helper"

class BlackFridayPacksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    travel_to Time.find_zone!("America/Sao_Paulo").local(2026, 11, 20, 12)
    @user = users(:customer_b2b)
    sign_in @user
    @attributes = { business_name: "Loja da Vila", offer: "Black Friday: roupas com 30% de desconto", style: "animado", show_cta: false }
    stub_request(:get, %r{https://api.stripe.com/v1/prices}).to_return(status: 200, headers: { "Content-Type" => "application/json" },
      body: { object: "list", data: [ { id: "price_test_pack", unit_amount: 19990, currency: "brl", type: "one_time" } ] }.to_json)
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { id: "cs_test_pack", url: "https://checkout.stripe.com/c/pay/cs_test_pack" }.to_json
    )
  end

  teardown { travel_back }

  test "landing explains both offers and compares against ten individual purchases" do
    get root_path
    assert_response :success
    assert_select "#preco", text: /Black Friday/
    assert_select "#preco", text: /R\$ 199,90/
    assert_select "#preco", text: /R\$ 19,99/
    assert_select "#preco", text: /R\$ 99,10/
    assert_select "#preco a[href=?]", new_campaign_pack_path
  end

  test "purchase is server priced and grants nothing before verified payment" do
    assert_no_enqueued_jobs only: GenerateLyricsJob do
      assert_difference [ "CampaignPack.count", "Order.count" ], 1 do
        post campaign_packs_path, params: { price_cents: 1, quantity: 1000, status: "paid" }
      end
    end
    pack = CampaignPack.last
    assert_equal 10, pack.quantity
    assert_equal 19990, pack.order.price_cents
    assert_equal "BRL", pack.order.currency
    assert_equal 0, @user.available_campaign_credits
    assert_redirected_to "https://checkout.stripe.com/c/pay/cs_test_pack"
  end

  test "payment success parameter cannot grant credits" do
    pack = create_pack
    get campaign_pack_path(pack, payment: "processing", status: "paid")
    assert_response :success
    assert_equal 0, @user.available_campaign_credits
    assert pack.order.reload.pending?
  end

  test "fulfillment checks amount currency and persisted session then grants ten credits once" do
    pack = create_pack
    pack.order.update!(stripe_session_id: "cs_test_pack")
    valid = { "id" => "cs_test_pack", "payment_status" => "paid", "amount_total" => 19990, "currency" => "brl", "payment_intent" => "pi_test_pack" }
    [ valid.merge("amount_total" => 1), valid.merge("currency" => "usd"), valid.merge("id" => "cs_test_other"), valid.merge("payment_status" => "unpaid") ].each do |data|
      assert Stripe::CheckoutFulfillment.call(order: pack.order, session_data: data).failure?
      assert_equal 0, @user.available_campaign_credits
    end
    assert_no_enqueued_jobs only: GenerateLyricsJob do
      2.times { assert Stripe::CheckoutFulfillment.call(order: pack.order, session_data: valid).success? }
    end
    assert_equal 10, @user.available_campaign_credits
    assert_equal "pi_test_pack", pack.order.reload.stripe_payment_intent_id
  end

  test "creating campaign consumes one owned paid credit without checkout and replay consumes none" do
    pack = create_pack(paid: true)
    token = SecureRandom.uuid
    assert_difference "Campaign.count", 1 do
      2.times do
        post campaigns_path, params: { campaign: @attributes.merge(creation_token: token), use_credit: "1" }
        assert_response :redirect
      end
    end
    campaign = Campaign.last
    assert_equal pack.id, campaign.order.campaign_pack_id
    assert_equal "paid", campaign.order.status
    assert_nil campaign.order.stripe_session_id
    assert_equal 9, @user.available_campaign_credits
    assert_not_requested :post, "https://api.stripe.com/v1/checkout/sessions"
  end

  test "invalid campaign does not consume a credit" do
    create_pack(paid: true)
    assert_no_difference [ "Campaign.count", "Order.count" ] do
      post campaigns_path, params: { campaign: @attributes.merge(offer: ""), use_credit: "1" }
    end
    assert_response :unprocessable_entity
    assert_equal 10, @user.available_campaign_credits
  end

  test "other users credits never fund a campaign" do
    create_pack(paid: true, user: users(:customer_other))
    assert_no_difference "Campaign.count" do
      post campaigns_path, params: { campaign: @attributes, use_credit: "1" }
    end
    assert_response :unprocessable_entity
    assert_equal 0, @user.available_campaign_credits
  end

  test "last credit cannot be spent twice and depleted balance does not silently open checkout" do
    pack = create_pack(paid: true, quantity: 1)
    post campaigns_path, params: { campaign: @attributes, use_credit: "1" }
    assert_equal 0, @user.available_campaign_credits
    assert_no_difference "Campaign.count" do
      post campaigns_path, params: { campaign: @attributes, use_credit: "1" }
    end
    assert_response :unprocessable_entity
    assert_not_requested :post, "https://api.stripe.com/v1/checkout/sessions"
    assert_equal 1, pack.funded_orders.count
  end

  test "refunded purchase removes unused credits" do
    pack = create_pack(paid: true)
    pack.order.cancel!
    pack.order.refund!
    assert_equal 0, @user.available_campaign_credits
  end

  test "private purchase cannot be read or checked out by another customer" do
    pack = create_pack(user: users(:customer_other))
    get campaign_pack_path(pack)
    assert_response :not_found
    sign_in @user
    post checkout_order_path(pack.order)
    assert_response :not_found
  end

  test "promotion closes but paid credits remain usable after Black Friday" do
    create_pack(paid: true)
    travel_to Time.find_zone!("America/Sao_Paulo").local(2026, 11, 28, 12)
    assert_no_difference "Order.count" do
      post campaign_packs_path
    end
    assert_redirected_to root_path(anchor: "preco")
    get root_path
    assert_select "#preco a[href=?]", new_campaign_pack_path, count: 0
    post campaigns_path, params: { campaign: @attributes, use_credit: "1" }
    assert_response :redirect
    assert_equal 9, @user.available_campaign_credits
  end

  private

  def create_pack(paid: false, user: @user, quantity: 10)
    order = user.orders.create!(reference: Orders::ReferenceGenerator.generate!, brand: "b2b", locale: "pt", tier: "starter",
      currency: "BRL", price_cents: 19990, delivery_email: user.email, lyrics_regen_limit: 20, music_regen_limit: 2)
    pack = CampaignPack.create!(order: order, quantity: quantity, offer_code: "black_friday_2026")
    order.mark_paid! if paid
    pack
  end
end
