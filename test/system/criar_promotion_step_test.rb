require "application_system_test_case"
require "warden/test/helpers"
require "tmpdir"
require "fileutils"

# Passo 1 do Criar no navegador (tarefa 4 do plano "caminho B"): contador, chips de contato
# ("Sem faixa" liga e desliga show_cta), fotos que se somam, ordem pelas setas e envio.
# A Stripe fica indisponível de propósito: o servidor salva a campanha e volta ao passo 3.
class CriarPromotionStepSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  PHOTOS_LABEL = "Fotos do produto ou do negócio (opcional)".freeze
  CONTACT_LABEL = "WhatsApp, endereço ou @Instagram".freeze
  PHOTO_INPUT = 'input[type="file"][name="campaign[photos][]"]'.freeze
  SHOW_CTA = 'input[name="campaign[show_cta]"]'.freeze

  setup do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
    @tmp_dirs = []
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
    @tmp_dirs.each { |dir| FileUtils.rm_rf(dir) }
  end

  test "typing updates the offer counter, the preview and the big borderless offer field" do
    visit new_campaign_path
    assert_selector ".criar[data-step='1']"
    assert_selector '[data-campaign-form-target="offerCount"]', text: "0/#{Campaign::OFFER_MAX_LENGTH}"
    style = page.evaluate_script(<<~JS)
      (() => {
        const style = getComputedStyle(document.querySelector("#campaign_offer"))
        return { resize: style.resize, fontSize: style.fontSize, fontWeight: style.fontWeight }
      })()
    JS
    assert_equal "none", style["resize"], "o campo da oferta não pode ter alça de redimensionar"
    assert_equal "24px", style["fontSize"]
    assert_equal "700", style["fontWeight"]

    offer = "Pizza em dobro na terça"
    fill_in "Qual é a oferta ou novidade?", with: offer
    assert_selector '[data-campaign-form-target="offerCount"]', text: "#{offer.length}/#{Campaign::OFFER_MAX_LENGTH}"
    assert_selector '[data-campaign-form-target="previewOffer"]', text: offer
    fill_in "Nome do seu negócio", with: "Pizzaria da Vila"
    assert_selector '[data-campaign-form-target="previewBusiness"]', text: "Pizzaria da Vila"
    fill_in CONTACT_LABEL, with: "@pizzariadavila"
    assert_selector '[data-campaign-form-target="previewContact"]', text: "@pizzariadavila"
    assert_selector '[data-campaign-form-target="previewCta"]', text: "Peça pelo WhatsApp"
    assert_no_javascript_errors
  end

  test "choosing a contact chip swaps the placeholder, the inputmode and the strip text in the preview" do
    visit new_campaign_path
    assert_contact_matches_hint "Peça pelo WhatsApp"
    assert_checked_cta "Peça pelo WhatsApp"
    [ "Venha nos visitar", "Saiba mais no Instagram", "Reserve seu horário" ].each do |option|
      choose_chip option
      assert_checked_cta option
      assert_contact_matches_hint option
      assert_equal "true", contact_attribute("required").to_s
      assert_selector '[data-campaign-form-target="previewCta"]', text: option
      assert_equal "1", show_cta_value
    end
    assert_no_javascript_errors
  end

  test "the no strip chip turns show_cta off, hides the contact field and the preview strip, and the next option brings them back" do
    visit new_campaign_path
    assert_equal "1", show_cta_value
    fill_in CONTACT_LABEL, with: "@pizzariadavila"

    choose_chip "Sem faixa de contato"
    assert_checked_cta ""
    assert_equal "0", show_cta_value
    assert_no_field CONTACT_LABEL
    assert_no_selector '[data-campaign-form-target="ctaFields"]'
    assert_no_selector '[data-campaign-form-target="previewCtaPanel"]'
    assert page.evaluate_script('document.querySelector("#campaign_contact").required === false'), "sem faixa, o contato não é obrigatório"
    assert_equal "@pizzariadavila", page.evaluate_script('document.querySelector("#campaign_contact").value'), "o contato digitado é mantido"

    choose_chip "Peça pelo WhatsApp"
    assert_equal "1", show_cta_value
    assert_field CONTACT_LABEL, with: "@pizzariadavila"
    assert_selector '[data-campaign-form-target="previewCtaPanel"]'
    assert_contact_matches_hint "Peça pelo WhatsApp"
    assert page.evaluate_script('document.querySelector("#campaign_contact").required === true')
    assert_no_javascript_errors
  end

  test "submitting with the no strip chip saves show_cta false without a call to action" do
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    choose_chip "Sem faixa de contato"
    pay
    campaign = Campaign.last
    refute campaign.show_cta?
    assert_equal "", campaign.call_to_action
    assert_equal "", campaign.contact
    assert_equal campaign.offer, campaign.caption
    assert_no_javascript_errors
  end

  test "submitting with a contact chip saves the option, the contact and the photo" do
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Café com pão por R$ 12 nesta terça."
    choose_chip "Venha nos visitar"
    fill_in CONTACT_LABEL, with: "Rua das Flores, 120"
    attach_file PHOTOS_LABEL, Rails.root.join("public/icon.png"), make_visible: true
    pay
    campaign = Campaign.last
    assert campaign.show_cta?
    assert_equal "Venha nos visitar", campaign.call_to_action
    assert_equal "Rua das Flores, 120", campaign.contact
    assert_equal 1, campaign.product_photos.size
    assert_no_javascript_errors
  end

  test "photos chosen in separate picks add up to the limit and a rejected batch keeps the selection" do
    initial = Campaigns::PhotoLimit::INITIAL
    visit new_campaign_path
    assert_equal initial, page.all(".ui-slots .ui-slot", visible: :all).size
    attach_file PHOTOS_LABEL, photo_files("um.jpg"), make_visible: true
    assert_photo_names %w[um.jpg]
    attach_file PHOTOS_LABEL, photo_files("dois.jpg"), make_visible: true
    assert_photo_names %w[um.jpg dois.jpg]
    assert_equal 2, page.all(".ui-slots figure.ui-slot img").size
    assert_equal initial - 2, page.all(".ui-slots label.ui-slot-empty").size

    attach_file PHOTOS_LABEL, photo_files("t1.jpg", "t2.jpg", "t3.jpg", "t4.jpg"), make_visible: true
    assert_selector "#campaign-photo-status", text: /já escolheu 2 de #{initial}/
    assert_photo_names %w[um.jpg dois.jpg]
    assert page.evaluate_script("document.querySelector('#{PHOTO_INPUT}').checkValidity()"), "lote rejeitado não pode deixar o campo inválido"
    assert_equal 2, page.all(".ui-slots figure.ui-slot img").size

    attach_file PHOTOS_LABEL, text_file("notas.txt"), make_visible: true
    assert_selector "#campaign-photo-status", text: /JPG, PNG ou WebP/
    assert_photo_names %w[um.jpg dois.jpg]
    assert page.evaluate_script("document.querySelector('#{PHOTO_INPUT}').checkValidity()")

    attach_file PHOTOS_LABEL, photo_files("tres.jpg", "quatro.jpg", "cinco.jpg"), make_visible: true
    assert_photo_names %w[um.jpg dois.jpg tres.jpg quatro.jpg cinco.jpg]
    assert_equal 0, page.all(".ui-slots label.ui-slot-empty").size
    attach_file PHOTOS_LABEL, photo_files("seis.jpg"), make_visible: true
    assert_selector "#campaign-photo-status", text: /já escolheu #{initial} de #{initial}/
    assert_photo_names %w[um.jpg dois.jpg tres.jpg quatro.jpg cinco.jpg]
    assert_no_javascript_errors
  end

  test "arrows and Usar primeiro reorder the files in the displayed order and the submission keeps that order" do
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    fill_in CONTACT_LABEL, with: "@pizzariadavila"
    attach_file PHOTOS_LABEL, photo_files("a.jpg", "b.jpg", "c.jpg"), make_visible: true
    assert_photo_names %w[a.jpg b.jpg c.jpg]
    assert_selector '[data-campaign-form-target="previewPhoto"][src^="blob:"]'

    find("button[aria-label='Mover foto 1 para depois']").click
    assert_photo_names %w[b.jpg a.jpg c.jpg]
    find("button[aria-label='Usar foto 3 primeiro']").click
    assert_photo_names %w[c.jpg b.jpg a.jpg]
    assert_includes page.find(".ui-slots .ui-slot", match: :first).text, "Abre o vídeo"

    pay
    assert_equal %w[c.jpg b.jpg a.jpg], Campaign.last.product_photos.map { |photo| photo.filename.to_s }
    assert_no_javascript_errors
  end

  test "the photo controls are real buttons with 44 px targets" do
    visit new_campaign_path
    attach_file PHOTOS_LABEL, photo_files("a.jpg", "b.jpg", "c.jpg"), make_visible: true
    assert_photo_names %w[a.jpg b.jpg c.jpg]
    sizes = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('.ui-slots button[data-photo-action]:not([disabled])'))
        .filter(button => ["before", "after", "first", "remove"].includes(button.dataset.photoAction))
        .map(button => { const rect = button.getBoundingClientRect(); return { action: button.dataset.photoAction, width: rect.width, height: rect.height, tag: button.tagName } })
    JS
    assert_operator sizes.size, :>=, 6
    sizes.each do |size|
      assert_equal "BUTTON", size["tag"]
      assert_operator size["width"], :>=, 43.5, "alvo estreito demais: #{size.inspect}"
      assert_operator size["height"], :>=, 43.5, "alvo baixo demais: #{size.inspect}"
    end
  end

  test "choosing new photos replaces the saved ones and says so, and removing the new ones brings the saved back" do
    campaign = Campaign.create!(order: orders(:b2b_pending), business_name: "Landel", offer: "Casa com 03 quartos", contact: "@landel")
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), filename: "salva-1.jpg", content_type: "image/jpeg")
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "salva-2.png", content_type: "image/png")
    visit campaign_path(campaign)
    assert_selector ".criar[data-step='3']"
    click_button "Voltar"
    click_button "Voltar"
    assert_selector ".criar[data-step='1']"
    assert_equal 2, page.all(".ui-slots figure.ui-slot img").size
    assert_equal 2, page.all('input[name="campaign[photo_order][]"]', visible: :all).size

    attach_file PHOTOS_LABEL, photo_files("nova.jpg"), make_visible: true
    assert_photo_names %w[nova.jpg]
    assert_equal 1, page.all(".ui-slots figure.ui-slot img").size
    assert_equal 0, page.all('input[name="campaign[photo_order][]"]', visible: :all).size
    assert_selector "#campaign-photo-status", text: /substitu/

    find("button[aria-label='Remover foto 1']").click
    assert_equal 2, page.all(".ui-slots figure.ui-slot img").size
    assert_equal 2, page.all('input[name="campaign[photo_order][]"]', visible: :all).size
    assert_equal 0, page.evaluate_script("document.querySelector('#{PHOTO_INPUT}').files.length")
    assert_no_javascript_errors
  end

  private

  def choose_chip(text)
    find("label", text: text).click
  end

  def assert_checked_cta(value)
    assert_equal value, page.evaluate_script('document.querySelector(\'input[name="campaign[call_to_action]"]:checked\').value')
  end

  def show_cta_value
    page.evaluate_script("document.querySelector('#{SHOW_CTA}').value")
  end

  def contact_attribute(name)
    page.evaluate_script("document.querySelector('#campaign_contact').#{name}")
  end

  def assert_contact_matches_hint(option)
    hint = ApplicationController.helpers.campaign_contact_hint(option)
    assert_equal hint[:placeholder], contact_attribute("placeholder")
    assert_equal hint[:inputmode], contact_attribute("inputMode")
  end

  def assert_photo_names(names)
    assert_selector ".ui-slots figure.ui-slot img", count: names.size
    assert_equal names, page.evaluate_script("Array.from(document.querySelector('#{PHOTO_INPUT}').files).map(file => file.name)")
    assert_equal names, page.all(".ui-slots figure.ui-slot img").map { |image| image[:alt] }, "a ordem das miniaturas (alt = nome do arquivo) deve ser a de input.files"
  end

  def pay
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    click_button "Pagar R$ 29,90"
    assert_text "Sua campanha está salva"
  end

  def photo_files(*names)
    dir = Dir.mktmpdir("criar-fotos")
    @tmp_dirs << dir
    paths = names.map do |name|
      path = File.join(dir, name)
      FileUtils.cp(Rails.root.join("public/demos/cafe-aurora.jpg"), path)
      path
    end
    paths.one? ? paths.first : paths
  end

  def text_file(name)
    dir = Dir.mktmpdir("criar-txt")
    @tmp_dirs << dir
    File.write(File.join(dir, name), "isto não é uma foto")
    File.join(dir, name)
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
