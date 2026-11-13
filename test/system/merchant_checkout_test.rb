require "application_system_test_case"

class MerchantCheckoutTest < ApplicationSystemTestCase
  test "a new merchant creates a campaign and returns from a simulated checkout to the lyrics" do
    visit new_order_path
    fill_in "Email", with: "browser-merchant@example.test"
    fill_in "Senha", with: "Campaign-Browser-123!", exact: true
    fill_in "Confirme a senha", with: "Campaign-Browser-123!"
    click_button "Criar conta"
    assert_text "O que vamos divulgar?"
    fill_in "Nome do seu negócio", with: "Café do Bairro"
    fill_in "Qual é a oferta ou novidade?", with: "Café com pão por R$ 12 nesta terça."
    fill_in "WhatsApp, endereço ou @Instagram", with: "@cafedobairro"
    attach_file "Fotos do produto ou do negócio (opcional)", Rails.root.join("public/icon.png"), make_visible: true
    assert_selector 'img[data-campaign-form-target="previewPhoto"][src^="blob:"]'
    click_button "Continuar"
    assert_text "Como sua promoção deve soar?"
    click_button "Continuar"
    assert_text "Confira e comece."
    assert_text "Você seguirá para o pagamento seguro pelo Stripe."
    assert_button "Pagar R$ 29,90"
    page.scroll_to(find(".campaign-form-actions"), align: :bottom)
    page.save_screenshot("/tmp/virajingle-direct-checkout.png")
    checkout_params = nil
    checkout = ->(**args) do
      checkout_params = args
      Stripe::Checkout::Session.construct_from(id: "cs_browser", url: args.fetch(:success_url))
    end
    payment = Stripe::Checkout::Session.construct_from(id: "cs_browser", payment_status: "paid",
      amount_total: 2990, currency: "brl", payment_intent: "pi_browser")
    Stripe::Checkout::Session.stub(:create, checkout) do
      Stripe::Checkout::Session.stub(:retrieve, payment) do
        assert_enqueued_jobs 1, only: GenerateLyricsJob do
          assert_difference [ "Campaign.count", "Order.count" ], 1 do
            click_button "Pagar R$ 29,90"
            assert_text "Preparando sua letra…"
          end
        end
      end
    end
    campaign = Campaign.joins(:order).find_by!(business_name: "Café do Bairro")
    assert_current_path order_chat_path(order_id: campaign.order_id)
    assert_equal 2990, checkout_params.fetch(:line_items).first.dig(:price_data, :unit_amount)
    assert_equal "cs_browser", campaign.order.stripe_session_id
    assert_equal 0, campaign.order.music_generations.count
    stub_request(:post, LyricsGenerator::MurekaLyricsClient::MUREKA_LYRICS_URL).to_return(
      status: 200, headers: { "Content-Type" => "application/json" },
      body: { title: "Café do Bairro", lyrics: "Café com pão por doze reais, nesta terça tem mais!" }.to_json
    )
    perform_enqueued_jobs(only: GenerateLyricsJob)
    assert_field "Sua letra", with: "Café com pão por doze reais, nesta terça tem mais!"
    assert_button "Gerar duas músicas"
    violations = page.driver.browser.logs.get(:browser).select { |entry| entry.message.match?(/violates.*Content Security Policy|Refused to (execute|load|connect)/i) }
    assert_empty violations, violations.map(&:message).join("\n")
  end
end
