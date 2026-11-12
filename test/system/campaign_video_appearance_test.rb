require "application_system_test_case"
require "warden/test/helpers"

class CampaignVideoAppearanceSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "merchant can use only a logo or leave both branding fields empty on mobile" do
    visit new_campaign_path
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    assert_no_selector '[data-campaign-form-target="previewLogo"]'
    fill_in "Qual é a oferta ou novidade?", with: "Casa com 03 quartos\nR$ 750.000"
    uncheck "Incluir faixa de contato no vídeo"
    attach_file "Logo da empresa (opcional)", Rails.root.join("public/brand/musical/virajingle-logo-white.png"), make_visible: true
    assert_selector '[data-campaign-form-target="previewLogo"][src^="blob:"]'
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    fill_in "Nome do seu negócio (opcional)", with: "Landel"
    assert_selector '[data-campaign-form-target="previewBusiness"]', text: "Landel"
    fill_in "Nome do seu negócio (opcional)", with: ""
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    assert_selector '[data-campaign-form-target="previewLogo"]'
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    page.scroll_to(find(".campaign-preview-wrap"), align: :top)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot("/tmp/virajingle-company-logo-mobile.png")
    click_button "Continuar"
    click_button "Continuar"
    click_button "Revisar minha campanha"
    assert_text "Confira sua promoção.", normalize_ws: true
    campaign = Campaign.last
    assert_equal "", campaign.business_name
    assert campaign.logo.attached?
    assert_empty campaign.product_photos
    click_link "Editar os dados"
    assert_selector '[data-campaign-form-target="previewLogo"][src*="rails/active_storage"]'
    check "Remover logo do vídeo"
    assert_no_selector '[data-campaign-form-target="previewLogo"]'
    assert_no_selector '[data-campaign-form-target="previewBusiness"]'
    click_button "Continuar"
    click_button "Continuar"
    click_button "Revisar minha campanha"
    assert_text "Confira sua promoção.", normalize_ws: true
    refute campaign.reload.logo.attached?
    assert_equal "", campaign.business_name
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

  test "merchant keeps offer lines and chooses an optional colored strip on desktop and mobile" do
    visit new_campaign_path
    fill_in "Nome do seu negócio", with: "Landel"
    fill_in "Qual é a oferta ou novidade?", with: "Casa com 03 quartos\nR$ 750.000"
    fill_in "WhatsApp, endereço ou @Instagram", with: "@landel"
    assert_offer_lines
    set_color "#6b21a8"
    assert_equal "rgb(107, 33, 168)", cta_style("backgroundColor")
    assert_equal "rgb(255, 255, 255)", cta_style("color")
    assert_equal "rgb(255, 255, 255)", page.evaluate_script('getComputedStyle(document.querySelector("[data-campaign-form-target=previewContact]")).color')
    page.save_screenshot("/tmp/virajingle-appearance-desktop.png")

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    assert_offer_lines
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.scroll_to(find(".campaign-preview-wrap"), align: :top)
    page.save_screenshot("/tmp/virajingle-appearance-mobile.png")
    uncheck "Incluir faixa de contato no vídeo"
    assert_no_selector '[data-campaign-form-target="previewCtaPanel"]'
    assert_no_selector '[data-campaign-form-target="ctaFields"]'
    check "Incluir faixa de contato no vídeo"
    assert_field "WhatsApp, endereço ou @Instagram", with: "@landel"
    assert_equal "rgb(107, 33, 168)", cta_style("backgroundColor")
    fill_in "WhatsApp, endereço ou @Instagram", with: ""
    uncheck "Incluir faixa de contato no vídeo"
    click_button "Continuar"
    assert_text "Como sua promoção deve soar?"
    click_button "Continuar"
    click_button "Revisar minha campanha"
    assert_text "Confira sua promoção.", normalize_ws: true
    campaign = Campaign.find_by!(business_name: "Landel")
    refute campaign.show_cta?
    assert_equal "#6b21a8", campaign.cta_color
    assert_equal "Casa com 03 quartos\nR$ 750.000", campaign.offer
    assert_equal "", campaign.contact
    click_link "Editar os dados"
    assert_unchecked_field "Incluir faixa de contato no vídeo"
    assert_no_selector '[data-campaign-form-target="previewCtaPanel"]'
    check "Incluir faixa de contato no vídeo"
    assert_equal "rgb(107, 33, 168)", cta_style("backgroundColor")
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
    set_color "#ffffff"
    assert_equal "rgb(23, 62, 50)", cta_style("color")
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

  def set_color(color)
    page.execute_script(<<~JS, color)
      const input = document.querySelector('[data-campaign-form-target="ctaColor"]')
      input.value = arguments[0]
      input.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end

  def cta_style(property)
    page.evaluate_script('getComputedStyle(document.querySelector("[data-campaign-form-target=previewCtaPanel]"))[arguments[0]]', property)
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
