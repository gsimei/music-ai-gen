require "application_system_test_case"
require "warden/test/helpers"

class CampaignVideoAppearanceSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "cancelled checkout uses the same payment screen and resumes the saved session" do
    order = orders(:b2b_pending)
    order.update!(stripe_session_id: "cs_cancelled_browser", currency: "BRL", price_cents: 2990)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 5", show_cta: false)
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "cafe.png", content_type: "image/png")
    session = Stripe::Checkout::Session.construct_from(id: "cs_cancelled_browser", status: "open", payment_status: "unpaid",
      url: campaign_path(campaign, checkout: "resumed"))
    Stripe::Checkout::Session.stub(:retrieve, session) do
      visit campaign_path(campaign)
      assert_text "Confira e comece."
      assert_text campaign.sound_summary
      assert_button "Pagar R$ 29,90"
      assert_selector '[data-campaign-form-target="previewPhoto"][src*="rails/active_storage"]', visible: :all # no desktop o passo 3 mostra o cartão de preço, não a prévia
      assert_no_button "Continuar"
      assert_no_button "Editar" # com o checkout iniciado não há passos 1 e 2 para voltar
      assert_selector ".ui-price", text: "R$ 29,90"
      assert_selector '[data-summary="promotion"]', text: "Café por R$"
      assert_no_javascript_errors
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      assert_no_difference [ "Campaign.count", "Order.count" ] do
        click_button "Pagar R$ 29,90"
        assert_current_path campaign_path(campaign, checkout: "resumed")
      end
      assert_button "Pagar R$ 29,90", disabled: false
      assert_no_javascript_errors
    end
  end

  test "merchant leaves the business name empty on mobile and the campaign is still saved" do
    visit new_campaign_path
    assert_selector "dialog.ui-stage[open]"
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    assert_no_selector '[data-campaign-form-target="previewLogo"]'
    fill_in "Qual é a oferta ou novidade?", with: "Casa com 03 quartos\nR$ 750.000"
    choose_chip("Sem faixa de contato")
    fill_in "Nome do seu negócio", with: "Landel"
    assert_selector '[data-campaign-form-target="previewBusiness"]', text: "Landel"
    fill_in "Nome do seu negócio", with: ""
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    assert_no_selector '[data-campaign-form-target="previewLogo"]'
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_no_selector ".ui-stage" # no celular a prévia não fica mais no fim da página: só abre pelo botão "Ver prévia"
    assert_button "Ver prévia"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot("/tmp/virajingle-company-name-empty-mobile.png")
    click_button "Continuar"
    click_button "Continuar"
    click_button "Pagar R$ 29,90"
    assert_text "Sua campanha está salva"
    campaign = Campaign.last
    assert_equal "", campaign.business_name
    refute campaign.logo.attached?
    assert_empty campaign.product_photos
    refute campaign.show_cta?
    click_button "Voltar"
    click_button "Voltar"
    assert_checked_field "Sem faixa de contato", visible: :all
    click_button "Ver prévia"
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    click_button "Voltar a preencher"
    click_button "Continuar"
    click_button "Continuar"
    click_button "Pagar R$ 29,90"
    assert_text "Sua campanha está salva"
    assert_equal "", campaign.reload.business_name
    refute campaign.logo.attached?
    assert_equal campaign.offer, campaign.caption
    assert_no_javascript_errors
  end

  test "studio saves logo-only branding and can restore the name while removing the logo" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Landel", offer: "Casa com 03 quartos", show_cta: false)
    campaign.update!(selected_music_asset: order_assets(:music_variant_a))
    visit order_chat_path(order_id: order.id)
    find(".creative-video-appearance summary").click unless find(".creative-video-appearance summary").find(:xpath, "..").matches_css?("details[open]")
    fill_in "Nome do seu negócio (opcional)", with: ""
    attach_file "Logo da empresa (opcional)", Rails.root.join("public/brand/musical/virajingle-logo-white.png"), make_visible: true
    assert_selector '.creative-video-appearance [data-campaign-form-target="previewLogo"][src^="blob:"]'
    assert_no_selector '.creative-video-appearance [data-campaign-form-target="previewBusiness"]'
    within ".creative-video-appearance" do
      click_button "Salvar aparência do vídeo"
    end
    assert_selector '.creative-video-appearance input[name="video_revision"][value="1"]', visible: :all
    assert_selector "#campaign-project-title-#{campaign.id}", text: "Campanha #{order.reference}"
    assert_equal "", campaign.reload.business_name
    assert campaign.logo.attached?
    find(".creative-video-appearance summary").click unless find(".creative-video-appearance summary").find(:xpath, "..").matches_css?("details[open]")
    fill_in "Nome do seu negócio (opcional)", with: "Landel Imóveis"
    check "Remover logo do vídeo"
    assert_no_selector '.creative-video-appearance [data-campaign-form-target="previewLogo"]'
    assert_selector '.creative-video-appearance [data-campaign-form-target="previewBusiness"]', text: "Landel Imóveis"
    within ".creative-video-appearance" do
      click_button "Salvar aparência do vídeo"
    end
    assert_selector '.creative-video-appearance input[name="video_revision"][value="2"]', visible: :all
    assert_selector "#campaign-project-title-#{campaign.id}", text: "Landel Imóveis"
    assert_equal "Landel Imóveis", campaign.reload.business_name
    refute campaign.logo.attached?
    assert_equal 0, order.generation_costs.count
    assert_no_javascript_errors
  end

  test "merchant keeps offer lines and chooses an optional strip on desktop and mobile" do
    visit new_campaign_path
    fill_in "Nome do seu negócio", with: "Landel"
    fill_in "Qual é a oferta ou novidade?", with: "Casa com 03 quartos\nR$ 750.000"
    fill_in "WhatsApp, endereço ou @Instagram", with: "@landel"
    assert_offer_lines
    page.save_screenshot("/tmp/virajingle-appearance-desktop.png")

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_no_selector ".ui-stage" # fechada no celular
    click_button "Ver prévia"
    assert_offer_lines
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot("/tmp/virajingle-appearance-mobile.png")
    click_button "Voltar a preencher"
    choose_chip("Sem faixa de contato")
    assert_equal "0", page.evaluate_script('document.querySelector(\'input[name="campaign[show_cta]"]\').value')
    assert page.evaluate_script('document.querySelector(\'[data-campaign-form-target="previewCtaPanel"]\').hidden')
    assert_no_selector '[data-campaign-form-target="ctaFields"]'
    choose_chip("Peça pelo WhatsApp")
    assert_equal "1", page.evaluate_script('document.querySelector(\'input[name="campaign[show_cta]"]\').value')
    assert_field "WhatsApp, endereço ou @Instagram", with: "@landel"
    assert_not page.evaluate_script('document.querySelector(\'[data-campaign-form-target="previewCtaPanel"]\').hidden')
    fill_in "WhatsApp, endereço ou @Instagram", with: ""
    choose_chip("Sem faixa de contato")
    click_button "Continuar"
    assert_text "Como sua promoção deve soar?"
    click_button "Continuar"
    click_button "Pagar R$ 29,90"
    assert_text "Sua campanha está salva"
    campaign = Campaign.find_by!(business_name: "Landel")
    refute campaign.show_cta?
    assert_equal "", campaign.call_to_action
    assert_equal "#d6f36b", campaign.cta_color # o Criar não escolhe cor: vale o padrão do servidor
    assert_equal "Casa com 03 quartos\nR$ 750.000", campaign.offer
    assert_equal "", campaign.contact
    click_button "Voltar"
    click_button "Voltar"
    assert_checked_field "Sem faixa de contato", visible: :all
    assert_no_selector '[data-campaign-form-target="ctaFields"]'
    assert page.evaluate_script('document.querySelector(\'[data-campaign-form-target="previewCtaPanel"]\').hidden')
    choose_chip("Peça pelo WhatsApp")
    assert_field "WhatsApp, endereço ou @Instagram"
    assert_no_javascript_errors
  end

  test "studio saves the strip and guards approval while appearance has unsaved changes" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Landel", offer: "Casa com 03 quartos\nR$ 750.000",
      contact: "@landel", call_to_action: "Saiba mais no Instagram", style: "animado")
    asset = order_assets(:music_variant_a)
    asset.campaign_audio.attach(io: StringIO.new("excerpt"), filename: "excerpt.m4a", content_type: "audio/mp4", metadata: { preview_revision: 0, duration_seconds: 30 })
    asset.audition_audio.attach(io: StringIO.new("protected"), filename: "audition.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
    asset.update!(campaign_preview_status: "ready")
    campaign.update!(selected_music_asset: order_assets(:music_variant_a))
    visit order_chat_path(order_id: order.id)
    find(".creative-video-appearance summary").click unless find(".creative-video-appearance summary").find(:xpath, "..").matches_css?("details[open]")
    set_color "#6b21a8"
    assert_equal "rgb(107, 33, 168)", cta_style("backgroundColor", within: ".creative-video-appearance")
    assert_equal "rgb(255, 255, 255)", cta_style("color", within: ".creative-video-appearance")
    assert_equal "rgb(255, 255, 255)", page.evaluate_script('getComputedStyle(document.querySelector(".creative-video-appearance [data-campaign-form-target=previewContact]")).color')
    set_color "#ffffff"
    assert_equal "rgb(23, 62, 50)", cta_style("color", within: ".creative-video-appearance")
    within ".creative-video-setup" do
      click_button "Gerar meu vídeo"
    end
    assert_text "Salve ou envie a alteração"
    within ".creative-video-appearance" do
      click_button "Salvar aparência do vídeo"
    end
    assert_selector '.creative-video-appearance input[name="video_revision"][value="1"]', visible: :all
    assert_equal "#ffffff", campaign.reload.cta_color
    find(".creative-video-appearance summary").click unless find(".creative-video-appearance summary").find(:xpath, "..").matches_css?("details[open]")
    uncheck "Incluir faixa de contato no vídeo"
    within ".creative-video-appearance" do
      click_button "Salvar aparência do vídeo"
    end
    assert_selector ".creative-video-appearance summary", text: "Ajustar nome, logo e faixa · sem faixa"
    assert_no_selector ".jp-summary-contact"
    refute campaign.reload.show_cta?
    assert_equal 2, campaign.video_revision
    assert_equal 1, order.completed_music_rounds
    assert_equal 0, order.generation_costs.count
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    find(".creative-video-appearance summary").click unless find(".creative-video-appearance summary").find(:xpath, "..").matches_css?("details[open]")
    check "Incluir faixa de contato no vídeo"
    page.scroll_to(find(".creative-video-appearance"), align: :top)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot("/tmp/virajingle-appearance-studio-mobile.png")
    assert_no_javascript_errors
  end

  private

  def assert_offer_lines
    assert page.evaluate_script('!!document.querySelector("dialog.ui-stage [data-campaign-form-target=previewOffer]")'), "a oferta da prévia vive dentro do dialog.ui-stage"
    refute page.evaluate_script('document.querySelector("[data-campaign-form-target=previewOffer]").classList.contains("campaign-offer-text")'), "a prévia nova não usa a classe legada"
    assert_equal "Casa com 03 quartos\nR$\u00a0750.000", page.evaluate_script('document.querySelector("[data-campaign-form-target=previewOffer]").textContent')
    assert_equal "pre-wrap", page.evaluate_script('getComputedStyle(document.querySelector("[data-campaign-form-target=previewOffer]")).whiteSpace')
    rectangles = page.evaluate_script(<<~JS)
      (() => {
        const text = document.querySelector("[data-campaign-form-target=previewOffer]").firstChild
        const range = document.createRange()
        range.setStart(text, text.textContent.indexOf("R$"))
        range.setEnd(text, text.length)
        return range.getClientRects().length
      })()
    JS
    assert_equal 1, rectangles, "Currency and amount must share a rendered line"
  end

  # Chips ficam no meio do formulário; no celular a barra de ação fixa não pode interceptar o clique.
  def choose_chip(text)
    chip = find("label", text: text)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", chip)
    chip.click
  end

  def set_color(color)
    page.execute_script(<<~JS, color)
      const input = document.querySelector('[data-campaign-form-target="ctaColor"]')
      input.value = arguments[0]
      input.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end

  def cta_style(property, within: nil)
    selector = [ within, "[data-campaign-form-target=previewCtaPanel]" ].compact.join(" ")
    page.evaluate_script("getComputedStyle(document.querySelector(arguments[1]))[arguments[0]]", property, selector)
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
