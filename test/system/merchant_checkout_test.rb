require "application_system_test_case"

class MerchantCheckoutTest < ApplicationSystemTestCase
  test "a new merchant creates a campaign and returns from a simulated checkout to the lyrics" do
    visit new_order_path
    assert_selector ".criar[data-step='1']"
    creation_token = find('input[name="campaign[creation_token]"]', visible: false).value
    fill_in "Nome do seu negócio", with: "Café do Bairro"
    fill_in "Qual é a oferta ou novidade?", with: "Café com pão por R$ 12 nesta terça."
    assert_selector '[data-campaign-form-target="offerCount"]', text: "#{"Café com pão por R$ 12 nesta terça.".length}/#{Campaign::OFFER_MAX_LENGTH}"
    assert_checked_field "Peça pelo WhatsApp", visible: :all
    fill_in "WhatsApp, endereço ou @Instagram", with: "@cafedobairro"
    photo_paths = [ Rails.root.join("public/icon.png"), Rails.root.join("public/brand/virajingle-symbol.png") ]
    attach_file "Fotos do produto ou do negócio (opcional)", photo_paths, make_visible: true
    assert_selector ".ui-slots figure.ui-slot img", count: 2
    assert_selector ".ui-slots label.ui-slot-empty", count: Campaigns::PhotoLimit::INITIAL - 2
    click_button "Mover foto 2 para antes"
    assert_selector 'img[data-campaign-form-target="previewPhoto"][src^="blob:"]'
    click_button "Continuar"
    assert_text "Como sua promoção deve soar?"
    click_button "Continuar"
    assert_text "Confira e comece."
    assert_text "No próximo passo, crie sua conta ou entre para continuar ao pagamento."
    within('[data-summary="promotion"]') do
      assert_text "Café do Bairro"
      assert_text(/Café com pão por R\$[[:space:]]12 nesta terça\./)
      assert_text "Peça pelo WhatsApp · @cafedobairro"
    end
    within('[data-summary="sound"]') do
      assert_text "Pop · Escolher por mim · Animado"
      assert_text "Cantada em português do Brasil"
    end
    within('[data-summary="photos"]') do
      assert_selector "img", count: 2
      assert_text "2 fotos"
    end
    within(".ui-price") do
      assert_text "R$ 29,90"
      assert_text "Até #{Campaigns::MusicRounds::LIMIT} rodadas"
    end
    assert_button "Continuar para o pagamento"
    page.scroll_to(find(".ui-actionbar"), align: :bottom)
    page.save_screenshot("/tmp/virajingle-direct-checkout.png")
    assert_no_difference [ "Order.count", "Campaign.count", "ActiveStorage::Blob.count" ] do
      click_button "Continuar para o pagamento"
      assert_text "Sua campanha está guardada neste navegador."
    end
    fill_in "Email", with: "browser-merchant@example.test"
    fill_in "Senha", with: "Campaign-Browser-123!", exact: true
    fill_in "Confirme a senha", with: "Different-Password-123!"
    assert_no_difference [ "User.count", "Order.count", "Campaign.count", "ActiveStorage::Blob.count" ] do
      click_button "Criar conta"
      assert_selector "form#new_user"
      assert_text "Sua campanha está guardada neste navegador."
    end
    fill_in "Senha", with: "Campaign-Browser-123!", exact: true
    fill_in "Confirme a senha", with: "Campaign-Browser-123!"
    checkout_params = nil
    checkout = ->(args, _options = {}) do
      checkout_params = args
      assert_empty Campaign.last.product_photos, "checkout must not persist browser images before payment"
      refute Campaign.last.logo.attached?
      Stripe::Checkout::Session.construct_from(id: "cs_browser", url: args.fetch(:success_url))
    end
    payment = Stripe::Checkout::Session.construct_from(id: "cs_browser", payment_status: "paid",
      amount_total: 2990, currency: "brl", payment_intent: "pi_browser")
    Stripe::Checkout::Session.stub(:create, checkout) do
      Stripe::Checkout::Session.stub(:retrieve, payment) do
        assert_enqueued_jobs 1, only: GenerateLyricsJob do
          assert_difference [ "Campaign.count", "Order.count", "User.count" ], 1 do
            click_button "Criar conta"
            assert_text "Preparando sua letra…"
          end
        end
      end
    end
    campaign = Campaign.joins(:order).find_by!(business_name: "Café do Bairro")
    assert_current_path order_chat_path(order_id: campaign.order_id)
    assert_equal "browser-merchant@example.test", campaign.order.user.email
    assert_equal creation_token, campaign.order.creation_token
    assert_equal "Café com pão por R$ 12 nesta terça.", campaign.offer
    assert_equal "pop", campaign.musical_genre
    assert_equal "auto", campaign.vocal_gender
    assert_equal "animado", campaign.style
    assert campaign.show_cta?
    assert_equal "Peça pelo WhatsApp", campaign.call_to_action
    assert_equal "@cafedobairro", campaign.contact
    assert_equal photo_paths.reverse.map(&:basename).map(&:to_s), campaign.product_photos.map { |photo| photo.filename.to_s }
    campaign.product_photos.zip(photo_paths.reverse).each do |photo, path|
      assert_equal File.binread(path), photo.blob.download
    end
    assert_equal 2990, checkout_params.fetch(:line_items).first.dig(:price_data, :unit_amount)
    assert_equal "cs_browser", campaign.order.stripe_session_id
    assert_equal 0, campaign.order.music_generations.count
    stub_request(:post, LyricsGenerator::MurekaLyricsClient::MUREKA_LYRICS_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { title: "Café do Bairro", lyrics: "Café com pão por doze reais, nesta terça tem mais!" }.to_json
    )
    perform_enqueued_jobs(only: GenerateLyricsJob)
    assert_field "editable-lyrics", with: "Café com pão por doze reais, nesta terça tem mais!"
    assert_button "Aprovar letra e ouvir 2 versões"
    violations = page.driver.browser.logs.get(:browser).select { |entry| entry.message.match?(/violates.*Content Security Policy|Refused to (execute|load|connect)/i) }
    assert_empty violations, violations.map(&:message).join("\n")
  end
end
