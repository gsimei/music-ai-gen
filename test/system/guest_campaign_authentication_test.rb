require "application_system_test_case"

class GuestCampaignAuthenticationTest < ApplicationSystemTestCase
  setup do
    @customer = users(:customer_b2b)
    @password = "Existing-Customer-123!"
    @customer.update!(password: @password, password_confirmation: @password)
  end

  test "existing customer retries login and pays after cancellation without losing fields or photos" do
    prepare_draft
    click_button "Continuar para o pagamento"
    assert_text "Sua campanha está guardada neste navegador."
    click_link "Entrar", exact: true
    fill_in "Email", with: @customer.email
    fill_in "Senha", with: "wrong-password"
    click_button "Entrar na minha conta"
    assert_selector "form#new_user"
    fill_in "Senha", with: @password
    checkout = ->(args, _options = {}) { Stripe::Checkout::Session.construct_from(id: "cs_guest_cancelled", url: args.fetch(:cancel_url)) }
    unpaid = Stripe::Checkout::Session.construct_from(id: "cs_guest_cancelled", payment_status: "unpaid")
    Stripe::Checkout::Session.stub(:create, checkout) do
      Stripe::Checkout::Session.stub(:retrieve, unpaid) do
        assert_no_difference "ActiveStorage::Blob.count" do
          click_button "Entrar na minha conta"
          assert_text "Confira e comece."
          assert_selector '[data-summary="photos"] img', count: 2
          page.refresh
          assert_selector '[data-summary="photos"] img', count: 2
        end
      end
    end
    campaign = Campaign.last
    assert_equal @customer.id, campaign.order.user_id
    assert_equal @creation_token, campaign.order.creation_token
    assert_equal "Loja São João", campaign.business_name
    assert_equal "Black Friday: coleção com 20% de desconto", campaign.offer
    assert_equal false, campaign.show_cta?
    assert_equal "rock", campaign.musical_genre
    assert_equal "female", campaign.vocal_gender
    assert_equal "marcante", campaign.style
    assert_equal "Guitarra suave.\nRefrão fácil de cantar.", campaign.music_notes
    assert campaign.order.pending?
    assert_empty campaign.product_photos
    payment = Stripe::Checkout::Session.construct_from(id: "cs_guest_cancelled", payment_status: "paid",
      amount_total: 2990, currency: "brl", payment_intent: "pi_guest_existing")
    Stripe::Checkout::Session.stub(:retrieve, payment) do
      assert_no_difference [ "Campaign.count", "Order.count", "User.count" ] do
        assert_enqueued_jobs 1, only: GenerateLyricsJob do
          visit campaign_path(campaign, payment: "processing")
          assert_text "Preparando sua letra…"
        end
      end
    end
    assert_current_path order_chat_path(order_id: campaign.order_id)
    assert campaign.reload.payment_confirmed?
    refute campaign.media_pending?
    expected_photos = draft_photo_paths.reverse
    assert_equal expected_photos.map(&:basename).map(&:to_s), campaign.product_photos.map { |photo| photo.filename.to_s }
    campaign.product_photos.zip(expected_photos).each do |photo, path|
      assert_equal File.binread(path), photo.blob.download
    end
  end

  test "the sign in button preserves an unfinished draft without starting a payment" do
    visit new_campaign_path
    fill_in "Nome do seu negócio", with: "Loja em criação"
    attach_file "Fotos do produto ou do negócio (opcional)", Rails.root.join("public/icon.png"), make_visible: true
    assert_selector ".ui-slots figure.ui-slot img", count: 1
    within(".studio-app-header") { click_button "Entrar" }
    assert_text "Sua campanha está guardada neste navegador."
    fill_in "Email", with: @customer.email
    fill_in "Senha", with: @password
    assert_no_difference "Order.count" do
      click_button "Entrar na minha conta"
      assert_selector ".criar[data-step='1']"
      assert_field "Nome do seu negócio", with: "Loja em criação"
      assert_selector ".ui-slots figure.ui-slot img", count: 1
    end
    assert_not_requested :post, "https://api.stripe.com/v1/checkout/sessions"
  end

  test "unavailable browser storage prevents account handoff and preserves the selected file" do
    prepare_draft
    page.execute_script("indexedDB.open = () => { throw new Error('unavailable') }")
    assert_no_difference [ "User.count", "Order.count", "Campaign.count", "ActiveStorage::Blob.count" ] do
      click_button "Continuar para o pagamento"
      assert_text "Não foi possível guardar as imagens neste navegador"
    end
    assert_equal 2, page.evaluate_script("document.getElementById('campaign_photos').files.length")
  end

  test "an existing credit balance is shown for confirmation instead of being spent automatically" do
    order = @customer.orders.create!(reference: Orders::ReferenceGenerator.generate!, brand: "b2b", locale: "pt", tier: "starter",
      currency: "BRL", price_cents: 19990, delivery_email: @customer.email, lyrics_regen_limit: 20, music_regen_limit: 2)
    pack = CampaignPack.create!(order: order, quantity: 10, offer_code: "black_friday_2026")
    order.mark_paid!
    prepare_draft
    click_button "Continuar para o pagamento"
    click_link "Entrar", exact: true
    fill_in "Email", with: @customer.email
    fill_in "Senha", with: @password
    assert_no_difference "Campaign.count" do
      click_button "Entrar na minha conta"
      assert_selector ".criar[data-step='3']"
      assert_selector '[data-summary="photos"] img', count: 2
      assert_button "Usar 1 crédito e criar campanha"
    end
    assert_equal 10, pack.remaining_credits
    assert_not_requested :post, "https://api.stripe.com/v1/checkout/sessions"
  end

  private

  def prepare_draft
    visit new_campaign_path
    @creation_token = find('input[name="campaign[creation_token]"]', visible: false).value
    fill_in "Nome do seu negócio", with: "Loja São João"
    fill_in "Qual é a oferta ou novidade?", with: "Black Friday: coleção com 20% de desconto"
    choose "Sem faixa de contato", allow_label_click: true
    attach_file "Fotos do produto ou do negócio (opcional)", draft_photo_paths, make_visible: true
    assert_selector ".ui-slots figure.ui-slot img", count: 2
    click_button "Mover foto 2 para antes"
    click_button "Continuar"
    choose "campaign_musical_genre_rock", allow_label_click: true
    choose "Voz feminina", allow_label_click: true
    choose "Marcante", allow_label_click: true
    click_button "Detalhes do som"
    fill_in "Detalhes do som", with: "Guitarra suave.\nRefrão fácil de cantar."
    click_button "Continuar"
    assert_text "Confira e comece."
  end

  def draft_photo_paths
    [ Rails.root.join("public/icon.png"), Rails.root.join("public/brand/virajingle-symbol.png") ]
  end
end
