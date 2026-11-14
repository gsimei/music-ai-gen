require "test_helper"

class GuestCampaignCreationTest < ActionDispatch::IntegrationTest
  setup do
    host! "b2b.lvh.me"
    @token = SecureRandom.uuid
    @attributes = { business_name: "Loja do Bairro", offer: "Coleção nova com 20% de desconto", style: "acolhedor",
      musical_genre: "acustico", vocal_gender: "female", music_notes: "Violão e palmas leves", show_cta: "0",
      media_upload_token: @token, creation_token: @token }
  end

  test "a visitor can start the form without creating an account order or uploaded media" do
    assert_no_difference [ "User.count", "Order.count", "Campaign.count", "ActiveStorage::Blob.count" ] do
      get new_order_path
      assert_redirected_to new_campaign_path
      follow_redirect!
    end
    assert_response :success
    assert_select "form.ui-form"
    assert_select 'button[type="submit"]', text: "Continuar para o pagamento"
    assert_select 'form.ui-form[data-media-owner^="guest-"]'
    assert_select 'button[form="campaign-creation"][value="sign_in"]', text: "Entrar"
    assert_select "button", text: "Sair", count: 0
  end

  test "guest submission requests an account and signup resumes the same browser draft" do
    get new_campaign_path
    guest_owner = css_select("form.ui-form").first["data-media-owner"]
    assert_no_difference [ "User.count", "Order.count", "Campaign.count", "ActiveStorage::Blob.count" ] do
      post campaigns_path, params: { campaign: @attributes.merge(user_id: users(:customer_other).id, price_cents: 1, status: "paid") }
    end
    assert_redirected_to new_user_registration_path
    follow_redirect!
    assert_select "[data-guest-campaign-notice]", text: /Sua campanha está guardada/
    assert_select "a[href=?]", new_campaign_path(draft: @token)
    assert_difference "User.count", 1 do
      assert_no_difference "Order.count" do
        post user_registration_path, params: { user: { email: "guest-draft@example.test", password: "Campaign-Guest-123!", password_confirmation: "Campaign-Guest-123!" } }
      end
    end
    assert_redirected_to new_campaign_path(draft: @token)
    follow_redirect!
    assert_response :success
    assert_select "form.ui-form[data-media-owner=?]", User.last.id.to_s
    assert_select "form.ui-form[data-campaign-form-draft-owner-value=?]", guest_owner
    assert_select "form.ui-form[data-campaign-form-draft-token-value=?]", @token
    assert_select 'form.ui-form[data-campaign-form-resume-checkout-value="true"]'
    assert_select 'input[name="campaign[creation_token]"][value=?]', @token
  end

  test "existing customer can retry login and return to the same draft" do
    user = users(:customer_b2b)
    user.update!(password: "Existing-Customer-123!", password_confirmation: "Existing-Customer-123!")
    get new_campaign_path
    post campaigns_path, params: { campaign: @attributes }
    get new_user_session_path
    post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }
    assert_response :unprocessable_entity
    post user_session_path, params: { user: { email: user.email, password: "Existing-Customer-123!" } }
    assert_redirected_to new_campaign_path(draft: @token)
    follow_redirect!
    assert_select "form.ui-form[data-campaign-form-draft-token-value=?]", @token
    assert_select "form.ui-form[data-media-owner=?]", user.id.to_s
  end

  test "invalid fields or malformed tokens do not start the account handoff" do
    get new_campaign_path
    [ @attributes.merge(offer: ""), @attributes.merge(creation_token: "not-a-token"), @attributes.merge(music_notes: "x" * 241) ].each do |attributes|
      assert_no_difference [ "Order.count", "User.count" ] do
        post campaigns_path, params: { campaign: attributes }
      end
      assert_response :unprocessable_entity
    end
  end

  test "a draft token from another browser cannot restore a visitor's work" do
    get new_campaign_path
    post campaigns_path, params: { campaign: @attributes }
    stranger = open_session
    stranger.host! "b2b.lvh.me"
    stranger.get new_campaign_path(draft: @token)
    stranger.assert_response :success
    stranger.assert_select "form.ui-form[data-campaign-form-draft-token-value]", count: 0
    get new_campaign_path(draft: SecureRandom.uuid)
    assert_select "form.ui-form[data-campaign-form-draft-token-value]", count: 0
  end

  test "saved campaigns and checkout remain private" do
    order = orders(:b2b_pending)
    campaign = Campaign.create!(order: order, offer: "Oferta privada", style: "animado", show_cta: false)
    get campaign_path(campaign)
    assert_redirected_to new_user_session_path
    post checkout_order_path(order)
    assert_redirected_to new_user_session_path
  end
end
