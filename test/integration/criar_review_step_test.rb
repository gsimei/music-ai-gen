require "test_helper"

# Passo 3 do Criar, "Conferir e pagar" (tarefa 7 do plano "caminho B"): resumo editável em três
# blocos, cartão de preço floresta, avisos com ícone e campos com erro marcados. O único envio
# continua sendo o botão da barra de ação (coberto em criar_shell_test.rb).
class CriarReviewStepTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  STRIPE_SENTENCE = "Você seguirá para o pagamento seguro pelo Stripe. A criação começa após a confirmação.".freeze
  LEAD = "Depois do pagamento você revisa a letra e ouve duas versões de música.".freeze
  NO_PHOTOS = "Sem fotos: criamos uma arte com a sua oferta.".freeze
  BLOCKS = { "promotion" => 0, "sound" => 1, "photos" => 0 }.freeze

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90, nesta terça", contact: "@pizzariadavila",
      call_to_action: "Peça pelo WhatsApp", style: "acolhedor", musical_genre: "forro", vocal_gender: "female" }
  end

  # ---------- título ----------

  test "the step opens with the question as an h2 with one italic word and the payment lead" do
    get new_campaign_path
    assert_response :success
    section = review_section
    heading = section.at_css("h2")
    assert heading, "o passo 3 precisa de um h2"
    assert_equal "Confira e comece.", heading.text.squish
    assert_equal [ "comece." ], heading.css("em").map { |node| node.text.squish }
    assert_includes section.text.squish, LEAD
  end

  # ---------- resumo ----------

  test "the summary has promotion, sound and photos blocks filled from the saved campaign" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    get campaign_path(campaign)
    assert_response :success
    assert_equal BLOCKS.keys, css_select(".ui-summary > [data-summary]").map { |node| node["data-summary"] }, "ordem dos blocos"

    promotion = block("promotion")
    assert_includes promotion.text, "Promoção"
    assert_equal "Pizzaria da Vila", target(promotion, "summaryBusiness").text.squish
    assert_equal @attributes[:offer], target(promotion, "summaryOffer").text.squish
    assert_equal "Peça pelo WhatsApp · @pizzariadavila", target(promotion, "summaryContact").text.squish

    sound = block("sound")
    assert_includes sound.text, "Som"
    assert_equal "Forró · Voz feminina · Acolhedor", target(sound, "soundSummary").text.squish
    assert_equal campaign.sound_summary, target(sound, "soundSummary").text.squish
    assert_includes sound.text.squish, "Cantada em português do Brasil"

    photos = block("photos")
    assert_includes photos.text, "Fotos"
    assert_includes photos.text.squish, NO_PHOTOS
    assert_empty photos.css("img")
  end

  test "a new campaign renders the three blocks from the defaults so the script can fill them" do
    get new_campaign_path
    assert_equal BLOCKS.keys, css_select(".ui-summary > [data-summary]").map { |node| node["data-summary"] }
    assert_equal "Pop · Escolher por mim · Animado", target(block("sound"), "soundSummary").text.squish
    assert target(block("promotion"), "summaryBusiness").key?("hidden"), "sem nome, a linha do nome fica escondida"
    assert_includes target(block("promotion"), "summaryContact").text, "Peça pelo WhatsApp"
  end

  test "without the strip the promotion block says so and omits the contact" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), show_cta: false, call_to_action: "", contact: ""))
    get campaign_path(campaign)
    contact = target(block("promotion"), "summaryContact")
    assert_equal "Sem faixa de contato", contact.text.squish
    assert_not_includes block("promotion").text, "@pizzariadavila"
  end

  test "saved photos appear as thumbnails in the photos block with their count" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), filename: "primeira.jpg", content_type: "image/jpeg")
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "segunda.png", content_type: "image/png")
    get campaign_path(campaign)
    photos = block("photos")
    thumbs = photos.css("img")
    assert_equal campaign.product_photos.map { |photo| rails_blob_path(photo) }, thumbs.map { |img| img["src"] }
    assert_match(/\b2 fotos\b/, photos.text)
    assert_not_includes photos.text.squish, NO_PHOTOS
    assert_equal 1, photos.css(%([data-campaign-form-target="summaryPhotos"])).size
  end

  # ---------- Editar ----------

  test "each block has an Editar button that goes back to its step" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    get campaign_path(campaign)
    BLOCKS.each do |key, step_index|
      buttons = block(key).css("button").select { |button| button.text.squish == "Editar" }
      assert_equal 1, buttons.size, "bloco #{key}: exatamente um botão Editar"
      button = buttons.first
      assert_equal "button", button["type"], "Editar nunca envia o formulário"
      assert_includes button["data-action"].to_s.split, "campaign-form#goToStep"
      assert_equal step_index.to_s, button["data-campaign-form-step-param"], "bloco #{key} volta ao passo de índice #{step_index}"
      assert button["aria-label"].to_s.start_with?("Editar "), "bloco #{key}: aria-label distinto, ex.: 'Editar promoção'"
    end
    labels = css_select(".ui-summary button").map { |button| button["aria-label"] }
    assert_equal labels.uniq, labels
  end

  test "a new campaign also offers the three Editar buttons" do
    get new_campaign_path
    assert_equal 3, css_select(".ui-summary button[data-action~='campaign-form#goToStep']").size
  end

  test "with a started checkout the summary comes from the server and Editar is gone together with steps 1 and 2" do
    order = orders(:b2b_pending)
    order.update!(stripe_session_id: "cs_review_started")
    campaign = Campaign.create!(@attributes.merge(order: order))
    open_session = Stripe::Checkout::Session.construct_from(id: "cs_review_started", status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/review")
    Stripe::Checkout::Session.stub(:retrieve, open_session) do
      get campaign_path(campaign)
    end
    assert_response :success
    assert_select "form.ui-form[action=?]", checkout_order_path(order)
    assert_select ".ui-summary button", count: 0
    assert_select "[data-action~='campaign-form#goToStep']", count: 0
    assert_select "textarea#campaign_offer, input#campaign_business_name, .ui-player, audio", count: 0
    assert_equal @attributes[:offer], target(block("promotion"), "summaryOffer").text.squish
    assert_equal "Forró · Voz feminina · Acolhedor", target(block("sound"), "soundSummary").text.squish
    assert_select ".ui-price", count: 1
  end

  # ---------- cartão de preço ----------

  test "there is one price card inside the form, with the plan name, the one time payment and the server price" do
    get new_campaign_path
    assert_select "form.ui-form .ui-price", count: 1
    card = css_select(".ui-price").first
    assert_includes card.text, "Campanha completa"
    assert_match(/pagamento único/i, card.text)
    amount = card.at_css(".ui-price-amount")
    assert amount, ".ui-price-amount com o preço em tipo display"
    assert_equal ApplicationController.helpers.campaign_price, amount.text.squish
    assert_equal "R$ 29,90", amount.text.squish
  end

  test "the price card shows the price frozen on the order" do
    order = orders(:b2b_pending)
    order.update!(price_cents: 3990, currency: "BRL")
    campaign = Campaign.create!(@attributes.merge(order: order))
    get campaign_path(campaign)
    amount = css_select(".ui-price .ui-price-amount").first
    assert amount, ".ui-price-amount ausente"
    assert_equal "R$ 39,90", amount.text.squish
  end

  test "the included list reads the rounds and rewrite limits from their constants and keeps video, mp3 and caption" do
    get new_campaign_path
    items = css_select(".ui-price li").map { |item| item.text.squish }
    assert_equal 4, items.size, items.inspect
    assert_match(/\AAté #{Campaigns::MusicRounds::LIMIT} rodadas com 2 versões/, items[0])
    assert_match(/\AAté #{BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :lyrics_regen_limit)} reescritas com IA e edição livre da letra/, items[1])
    assert_match(/vídeo vertical/i, items[2])
    assert_match(/MP3 e legenda/i, items[3])
  end

  test "changing the limits changes the card, so nothing is a literal" do
    original_config = BRANDS_CONFIG
    starter = original_config[:b2b][:tiers][:starter].merge(lyrics_regen_limit: 25)
    changed = original_config.merge(b2b: original_config[:b2b].merge(tiers: original_config[:b2b][:tiers].merge(starter: starter)))
    with_constant(Campaigns::MusicRounds, :LIMIT, 4) do
      with_constant(Object, :BRANDS_CONFIG, changed) do
        get new_campaign_path
      end
    end
    items = css_select(".ui-price li").map { |item| item.text.squish }
    assert_equal 4, items.size, items.inspect
    assert_match(/\AAté 4 rodadas/, items[0])
    assert_match(/\AAté 25 reescritas/, items[1])
  end

  test "the card never carries a pay button and the old total and included list are gone" do
    get new_campaign_path
    assert_select ".ui-price button, .ui-price [type=submit], .ui-price input[type=submit]", count: 0
    assert_select ".campaign-total, .campaign-included, .campaign-purchase", count: 0
    assert_select "form.ui-form button[type=submit]", count: 1
    assert_select "form.ui-form .ui-actionbar button[type=submit]", text: "Pagar R$ 29,90 e criar campanha"
  end

  test "the secure payment sentence stays on the page" do
    get new_campaign_path
    assert_includes css_select(".criar").first.text.squish, STRIPE_SENTENCE
  end

  # ---------- avisos e erros ----------

  test "a failed payment shows an alert with a hidden icon and keeps the form and the summary filled" do
    order = orders(:b2b_pending)
    order.update!(status: "payment_failed")
    campaign = Campaign.create!(@attributes.merge(order: order))
    get campaign_path(campaign)
    alert = css_select(".ui-alert[role=alert]").find { |node| node.text.include?("O pagamento não foi concluído.") }
    assert alert, "aviso .ui-alert[role=alert] de pagamento ausente"
    assert alert.at_css('svg[aria-hidden="true"]'), "o aviso leva um ícone SVG com aria-hidden"
    assert_select "textarea#campaign_offer", text: @attributes[:offer]
    assert_equal @attributes[:offer], target(block("promotion"), "summaryOffer").text.squish
    assert_select "form.ui-form[action=?]", campaign_path(campaign)
  end

  test "a validation error marks the field invalid, describes it and keeps what was typed" do
    assert_no_difference "Order.count" do
      post campaigns_path, params: { campaign: @attributes.merge(offer: "") }
    end
    assert_response :unprocessable_entity
    message = Campaign.new(offer: "").tap(&:valid?).errors[:offer].first
    alert = css_select(".ui-alert[role=alert]").find { |node| node.text.include?("Confira os campos abaixo") }
    assert alert, "aviso .ui-alert[role=alert] de validação ausente"
    assert alert.at_css('svg[aria-hidden="true"]')
    assert_includes alert.text, "Oferta"

    offer = css_select("textarea#campaign_offer").first
    assert_equal "true", offer["aria-invalid"]
    described = offer["aria-describedby"].to_s.split
    assert_includes described, "campaign-offer-help", "a dica continua descrevendo o campo"
    assert_operator described.size, :>=, 2, "a mensagem de erro entra no aria-describedby"
    texts = described.map { |id| css_select("##{id}").first&.text.to_s }
    assert texts.any? { |text| text.include?(message) }, "nenhum elemento de aria-describedby traz '#{message}': #{texts.inspect}"
    assert_empty described.reject { |id| css_select("##{id}").any? }, "aria-describedby aponta para ids inexistentes"

    assert_select "input#campaign_business_name[value=?]", "Pizzaria da Vila"
    assert_select "input#campaign_contact[value=?]", "@pizzariadavila"
    assert_select "input#campaign_contact[aria-invalid=true]", count: 0
    assert_select "input#campaign_business_name[aria-invalid=true]", count: 0
  end

  test "any invalid field gets the same treatment, not only the offer" do
    post campaigns_path, params: { campaign: @attributes.merge(business_name: "x" * (Campaign::BUSINESS_NAME_MAX_LENGTH + 1)) }
    assert_response :unprocessable_entity
    field = css_select("input#campaign_business_name").first
    assert_equal "true", field["aria-invalid"]
    described = field["aria-describedby"].to_s.split
    assert_includes described, "campaign-business-help"
    assert_operator described.size, :>=, 2
    assert_empty described.reject { |id| css_select("##{id}").any? }
  end

  # ---------- só em development ----------

  test "the no charge test button does not exist outside development" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    get campaign_path(campaign)
    assert_select "button, input[type=submit]", text: "Testar sem cobrança", count: 0
    assert_select "form[action=?]", "/campaigns/#{campaign.id}/test_payment", count: 0
  end

  private

  def review_section
    sections = css_select('form.ui-form section[data-campaign-form-target="step"]')
    assert_equal 3, sections.size, "esperava 3 passos, achei #{sections.size}"
    sections.last
  end

  def block(key)
    node = css_select(%(.ui-summary > [data-summary="#{key}"])).first
    assert node, "bloco de resumo #{key} ausente"
    node
  end

  def target(scope, name)
    node = scope.at_css(%([data-campaign-form-target="#{name}"]))
    assert node, "alvo campaign-form #{name} ausente"
    node
  end

  # Troca uma constante só durante o bloco e restaura no fim (as views leem a constante na hora de renderizar).
  def with_constant(owner, name, value)
    original = owner.const_get(name)
    silence_warnings { owner.const_set(name, value) }
    yield
  ensure
    silence_warnings { owner.const_set(name, original) }
  end
end
