require "test_helper"

# Passo 1 do Criar, "Sua promoção" (tarefa 4 do plano "caminho B"): nome, oferta com contador,
# contato em chips (mais "Sem faixa de contato") e fotos em espaços. Logo, cor e checkbox da faixa
# saem do Criar, mas o servidor continua aceitando esses parâmetros e nunca apaga o que já existe.
class CriarPromotionStepTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  CTA_RADIOS = 'input[type="radio"][name="campaign[call_to_action]"]'.freeze
  NO_STRIP_LABEL = "Sem faixa de contato".freeze
  STUDIO_NOTE = "Logo e cor da faixa você ajusta no estúdio, ao montar o vídeo, sem gastar rodada.".freeze

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90, nesta terça", contact: "@pizzariadavila",
      call_to_action: "Peça pelo WhatsApp", style: "animado" }
  end

  # ---------- nome ----------

  test "the business name is optional, limited by the shared constant and explained" do
    get new_campaign_path
    assert_response :success
    assert_select "label[for=campaign_business_name]", text: "Nome do seu negócio"
    assert_select %(input#campaign_business_name[maxlength="#{Campaign::BUSINESS_NAME_MAX_LENGTH}"][data-campaign-form-target="business"])
    assert_select "input#campaign_business_name:not([required])"
    assert_select ".criar", text: /Aparece no vídeo e é cantado na música\./
  end

  # ---------- oferta ----------

  test "the offer is a required big field with a character counter from the shared constant" do
    get new_campaign_path
    assert_select "label[for=campaign_offer]", text: "Qual é a oferta ou novidade?"
    assert_select %(textarea#campaign_offer[required][maxlength="#{Campaign::OFFER_MAX_LENGTH}"][data-campaign-form-target="offer"])
    assert_select '[data-campaign-form-target="offerCount"]', text: "0/#{Campaign::OFFER_MAX_LENGTH}"
  end

  test "the counter starts at the saved offer length" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), offer: "Casa com 03 quartos\nR$ 750.000"))
    get campaign_path(campaign)
    assert_select '[data-campaign-form-target="offerCount"]', text: "#{campaign.offer.length}/#{Campaign::OFFER_MAX_LENGTH}"
  end

  # ---------- contato ----------

  test "contact is a radio group with one chip per option, then the no strip chip, WhatsApp checked on a new campaign" do
    get new_campaign_path
    radios = css_select(CTA_RADIOS)
    assert_equal Campaign::CTA_OPTIONS + [ "" ], radios.map { |radio| radio["value"] }
    assert_equal [ "Peça pelo WhatsApp" ], radios.select { |radio| radio["checked"] }.map { |radio| radio["value"] }
    radios.each { |radio| assert_equal "ctaChoice", radio["data-campaign-form-target"] }
    group = radios.first.ancestors("fieldset").first
    assert group, "os chips de contato precisam estar num fieldset"
    assert group.at_css("legend")&.text.to_s.strip.present?, "o fieldset precisa de uma legend"
    (Campaign::CTA_OPTIONS + [ "" ]).each do |value|
      expected = value.presence || NO_STRIP_LABEL
      radio = radios.find { |candidate| candidate["value"] == value }
      assert_includes chip_text(radio), expected
    end
    assert_select ".ui-chip", minimum: Campaign::CTA_OPTIONS.size + 1
  end

  test "each chip carries the placeholder and inputmode its option puts in the contact field" do
    get new_campaign_path
    option_radios = css_select(CTA_RADIOS).select { |radio| Campaign::CTA_OPTIONS.include?(radio["value"]) }
    assert_equal Campaign::CTA_OPTIONS.size, option_radios.size, "um rádio por opção de CTA"
    option_radios.each do |radio|
      hint = ApplicationController.helpers.campaign_contact_hint(radio["value"])
      assert_equal hint[:placeholder], radio["data-contact-placeholder"], radio["value"]
      assert_equal hint[:inputmode], radio["data-contact-inputmode"], radio["value"]
    end
  end

  test "a new campaign sends the strip on, with a required phone contact" do
    get new_campaign_path
    hint = ApplicationController.helpers.campaign_contact_hint("Peça pelo WhatsApp")
    assert_select %(section input[type="hidden"][name="campaign[show_cta]"][value="1"]), count: 1
    assert_select 'input[type="checkbox"][name="campaign[show_cta]"]', count: 0
    assert_select "label[for=campaign_contact]", text: "WhatsApp, endereço ou @Instagram"
    assert_select %(input#campaign_contact[required][maxlength="70"][placeholder="#{hint[:placeholder]}"][inputmode="#{hint[:inputmode]}"][data-campaign-form-target="contact"])
    assert_select '[data-campaign-form-target="ctaFields"]:not([hidden]) input#campaign_contact'
  end

  test "the show_cta hidden input lives inside the first step section so it is submitted with the step" do
    get new_campaign_path
    first_section = css_select('form.ui-form section[data-campaign-form-target="step"]').first
    assert first_section.at_css('input[type="hidden"][name="campaign[show_cta]"]'), "o hidden show_cta deve ficar dentro da section do passo 1"
    assert first_section.at_css(CTA_RADIOS), "os chips de contato ficam dentro da section do passo 1"
    assert first_section.at_css("input#campaign_contact")
  end

  test "a saved option outside the list becomes an extra checked chip before the no strip chip" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), call_to_action: "Peça agora"))
    get campaign_path(campaign)
    radios = css_select(CTA_RADIOS)
    assert_equal Campaign::CTA_OPTIONS + [ "Peça agora", "" ], radios.map { |radio| radio["value"] }
    assert_equal [ "Peça agora" ], radios.select { |radio| radio["checked"] }.map { |radio| radio["value"] }
    extra = radios.find { |radio| radio["value"] == "Peça agora" }
    generic = ApplicationController.helpers.campaign_contact_hint("Peça agora")
    assert_equal generic[:placeholder], extra["data-contact-placeholder"]
    assert_equal generic[:inputmode], extra["data-contact-inputmode"]
    assert_includes chip_text(extra), "Peça agora"
    assert_select %(input#campaign_contact[required][placeholder="#{generic[:placeholder]}"][inputmode="#{generic[:inputmode]}"])
    assert_select 'input[type="hidden"][name="campaign[show_cta]"][value="1"]'
  end

  test "a saved campaign with the strip keeps its option, the hidden on and the contact required" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), call_to_action: "Reserve seu horário"))
    get campaign_path(campaign)
    checked = css_select(CTA_RADIOS).select { |radio| radio["checked"] }
    assert_equal [ "Reserve seu horário" ], checked.map { |radio| radio["value"] }
    assert_select 'input[type="hidden"][name="campaign[show_cta]"][value="1"]'
    assert_select %(input#campaign_contact[required][value="#{campaign.contact}"])
    assert_select '[data-campaign-form-target="ctaFields"]:not([hidden])'
    assert_select '[data-campaign-form-target="previewCtaPanel"]:not([hidden])'
  end

  test "without the strip the no strip chip is checked, the hidden is off and the contact panel is hidden" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), show_cta: false, contact: "", call_to_action: "Peça agora"))
    get campaign_path(campaign)
    radios = css_select(CTA_RADIOS)
    assert_equal Campaign::CTA_OPTIONS + [ "" ], radios.map { |radio| radio["value"] }, "sem faixa não há chip extra"
    assert_equal [ "" ], radios.select { |radio| radio["checked"] }.map { |radio| radio["value"] }
    assert_select 'input[type="hidden"][name="campaign[show_cta]"][value="0"]', count: 1
    assert_select "input#campaign_contact:not([required])"
    assert_select '[data-campaign-form-target="ctaFields"][hidden] input#campaign_contact'
    assert_select '[data-campaign-form-target="previewCtaPanel"][hidden]'
  end

  test "a stale default option saved with the strip off does not stay checked" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), show_cta: false, contact: ""))
    assert_equal "Peça pelo WhatsApp", campaign.call_to_action
    get campaign_path(campaign)
    checked = css_select(CTA_RADIOS).select { |radio| radio["checked"] }
    assert_equal [ "" ], checked.map { |radio| radio["value"] }
    assert_select 'input[type="hidden"][name="campaign[show_cta]"][value="0"]'
  end

  test "a rejected submission without the strip comes back with the no strip chip and the hidden off" do
    assert_no_difference "Order.count" do
      post campaigns_path, params: { campaign: @attributes.merge(offer: "", show_cta: "0", call_to_action: "", contact: "") }
    end
    assert_response :unprocessable_entity
    assert_equal [ "" ], css_select(CTA_RADIOS).select { |radio| radio["checked"] }.map { |radio| radio["value"] }
    assert_select 'input[type="hidden"][name="campaign[show_cta]"][value="0"]'
    assert_select "input#campaign_contact:not([required])"
    assert_select '[data-campaign-form-target="previewCtaPanel"][hidden]'
    assert_select "#campaign_business_name[value=?]", "Pizzaria da Vila"
  end

  test "a payment failure keeps the chosen option in the form" do
    order = orders(:b2b_pending)
    order.update!(status: "payment_failed")
    campaign = Campaign.create!(@attributes.merge(order: order, call_to_action: "Saiba mais no Instagram", contact: "@vila"))
    get campaign_path(campaign)
    assert_equal [ "Saiba mais no Instagram" ], css_select(CTA_RADIOS).select { |radio| radio["checked"] }.map { |radio| radio["value"] }
    assert_select "input#campaign_contact[value=?]", "@vila"
  end

  # ---------- o que sai do Criar ----------

  test "logo, color and the strip checkbox are gone from the Criar" do
    get new_campaign_path
    assert_select 'input[type="color"]', count: 0
    assert_select 'input[type="file"][name="campaign[logo]"]', count: 0
    assert_select "#campaign_logo", count: 0
    assert_select "#campaign_remove_logo", count: 0
    assert_select 'input[name="campaign[remove_logo]"]', count: 0
    assert_select 'input[name="campaign[cta_color]"]', count: 0
    assert_select 'input[type="checkbox"][name="campaign[show_cta]"]', count: 0
    assert_select "select#campaign_call_to_action", count: 0
    assert_select 'input[name="campaign[show_cta]"]', count: 1
    assert_select ".criar", text: /#{Regexp.escape(STUDIO_NOTE)}/
  end

  test "the Criar does not render the first step with legacy campaign or studio-field classes" do
    get new_campaign_path
    section = css_select('form.ui-form section[data-campaign-form-target="step"]').first
    classes = ([ section ] + section.css("[class]").to_a).flat_map { |node| node["class"].to_s.split }
    legacy = classes.grep(/\A(campaign-|studio-field|studio-button)/)
    assert_empty legacy, "classes legadas no passo 1: #{legacy.uniq.inspect}"
  end

  test "a color and a logo saved on the campaign survive an update that sends only the Criar fields" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), cta_color: "#6b21a8"))
    campaign.logo.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "logo.png", content_type: "image/png")
    original_blob = campaign.logo.blob.id
    patch campaign_path(campaign), params: { campaign: { business_name: "Pizzaria da Vila", offer: "Oferta nova", show_cta: "1",
      call_to_action: "Venha nos visitar", contact: "Rua das Flores, 120", style: "animado", musical_genre: "pop", vocal_gender: "auto", music_notes: "" } }
    assert_redirected_to campaign_path(campaign)
    campaign.reload
    assert_equal original_blob, campaign.logo.blob.id
    assert_equal "#6b21a8", campaign.cta_color
    assert_equal "Oferta nova", campaign.offer
    get campaign_path(campaign)
    assert_select '[data-campaign-form-target="previewLogo"][src]'
    assert_select '[data-campaign-form-target="previewCtaPanel"][style*="--campaign-cta-color: #6b21a8"]'
  end

  test "the server accepts the no strip contract the chip produces and leaves the call out of briefing and caption" do
    assert_difference [ "Campaign.count", "Order.count" ], 1 do
      post campaigns_path, params: { campaign: { business_name: "", offer: "Pizza em dobro na terça", show_cta: "0", call_to_action: "", contact: "", style: "animado" } }
    end
    campaign = Campaign.last
    refute campaign.show_cta?
    assert_equal "", campaign.call_to_action
    refute_includes campaign.order.briefing.about, "Chamada:"
    assert_equal campaign.offer, campaign.caption
  end

  # ---------- fotos ----------

  test "photos are a row of INITIAL slots, empty ones open the native picker and the first says it opens the video" do
    get new_campaign_path
    initial = Campaigns::PhotoLimit::INITIAL
    assert_select '.ui-slots[data-campaign-form-target="photoList"]' do
      assert_select ".ui-slot", count: initial
      assert_select "label.ui-slot.ui-slot-empty[for=campaign_photos]", count: initial
      assert_select "figure", count: 0
    end
    assert_includes css_select(".ui-slots .ui-slot").first.text, "Abre o vídeo"
    assert_equal 1, css_select(".ui-slots .ui-slot").count { |slot| slot.text.include?("Abre o vídeo") }
  end

  test "the file input keeps the multiple field, its accessible name and its descriptions" do
    get new_campaign_path
    assert_select %(input#campaign_photos[type="file"][multiple][name="campaign[photos][]"][accept="image/jpeg,image/png,image/webp"][data-campaign-form-target="photoInput"])
    assert_select "label[for=campaign_photos]", text: /Fotos do produto ou do negócio \(opcional\)/
    described = css_select("input#campaign_photos").first["aria-describedby"].to_s.split
    assert_includes described, "campaign-photo-help"
    assert_includes described, "campaign-photo-status"
    assert_select "#campaign-photo-status[role=status][data-campaign-form-target=photoStatus]"
    help = css_select("#campaign-photo-help").first.text
    assert_match(/\b#{Campaigns::PhotoLimit::INITIAL}\b/, help)
    assert_match(/\b#{Campaigns::PhotoLimit::MAX}\b/, help)
  end

  test "the number of slots, the help text and the limit value follow the INITIAL constant" do
    with_initial_photo_limit(8) do
      get new_campaign_path
      assert_select ".ui-slots .ui-slot", count: 8
      assert_select "form.ui-form[data-campaign-form-photo-limit-value=?]", "8"
      assert_match(/\b8\b/, css_select("#campaign-photo-help").first.text)
    end
    with_initial_photo_limit(3) do
      get new_campaign_path
      assert_select ".ui-slots .ui-slot", count: 3
    end
  end

  test "saved photos fill the first slots in photo_order, keep their hidden order fields and leave the rest empty" do
    post campaigns_path, params: { campaign: @attributes }
    campaign = Campaign.last
    campaign.photos.attach(%w[first second third].map { |name| photo_upload(name) })
    ids = campaign.product_photos.map(&:id)
    chosen = [ ids[2], ids[0], ids[1] ]
    patch campaign_path(campaign), params: { campaign: @attributes.merge(photo_order: chosen.map(&:to_s)) }
    get campaign_path(campaign)
    assert_response :success
    figures = css_select(".ui-slots figure.ui-slot[data-photo-id]")
    assert_equal chosen.map(&:to_s), figures.map { |figure| figure["data-photo-id"] }
    figures.each { |figure| assert figure.at_css("img[src]"), "cada foto salva tem miniatura" }
    assert_select 'input[type="hidden"][name="campaign[photo_order][]"]' do |inputs|
      assert_equal chosen.map(&:to_s), inputs.map { |input| input["value"] }
    end
    assert_select ".ui-slots label.ui-slot-empty[for=campaign_photos]", count: Campaigns::PhotoLimit::INITIAL - 3
    assert_includes css_select(".ui-slots .ui-slot").first.text, "Abre o vídeo"
    assert_match(/substitu/, css_select("#campaign-photo-status").first.text)
  end

  private

  def chip_text(radio)
    label = radio.ancestors("label").first || radio.document.at_css(%(label[for="#{radio['id']}"]))
    assert label, "o chip #{radio['value'].inspect} precisa de um label"
    label.text.squish
  end

  def photo_upload(name)
    Rack::Test::UploadedFile.new(StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), "image/jpeg", original_filename: "#{name}.jpg")
  end

  def with_initial_photo_limit(value)
    original = Campaigns::PhotoLimit::INITIAL
    silence_warnings { Campaigns::PhotoLimit.const_set(:INITIAL, value) }
    yield
  ensure
    silence_warnings { Campaigns::PhotoLimit.const_set(:INITIAL, original) }
  end
end
