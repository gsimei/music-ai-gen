require "test_helper"

# Prévia em arco do Criar (tarefa 5 do plano "caminho B"): um único <dialog class="ui-stage"> que
# fica aberto na coluna da direita no desktop e vira folha "Ver prévia" no celular. Um só conjunto
# de alvos preview*, porque o controller usa o primeiro de cada.
class CriarPreviewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PREVIEW_TARGETS = %w[previewOffer previewBusiness previewLogo previewCtaPanel previewCta previewContact previewPhoto previewThumb].freeze

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Landel", offer: "Casa com 03 quartos\nR$ 750.000", contact: "@landel",
      call_to_action: "Saiba mais no Instagram", style: "animado", cta_color: "#6b21a8" }
  end

  test "the preview is one dialog inside the form with a name and exactly one set of targets" do
    get new_campaign_path
    assert_response :success
    assert_select "form.ui-form dialog.ui-stage", count: 1
    assert_select "dialog.ui-stage[aria-label], dialog.ui-stage[aria-labelledby]", count: 1
    PREVIEW_TARGETS.each do |target|
      assert_select %([data-campaign-form-target="#{target}"]), count: 1
      # previewThumb mora no botão "Ver prévia", fora do dialog (teste abaixo)
      assert_select %(dialog.ui-stage [data-campaign-form-target="#{target}"]), count: 1 unless target == "previewThumb"
    end
    assert_select ".campaign-preview-wrap", count: 0
    assert_select ".campaign-poster", count: 0
  end

  test "the dialog is a framed phone with the arc label and the landing card, free of legacy classes" do
    get new_campaign_path
    assert_select "dialog.ui-stage", text: /Prévia · 9:16/
    assert_select "dialog.ui-stage", text: /Suas fotos\./
    assert_select "dialog.ui-stage", text: /Sua marca no refrão\./
    stage = css_select("dialog.ui-stage").first
    classes = ([ stage ] + stage.css("[class]").to_a).flat_map { |node| node["class"].to_s.split }
    assert_empty classes.grep(/\Acampaign-/), "classes legadas na prévia: #{classes.grep(/\Acampaign-/).uniq.inspect}"
  end

  test "there is a single Ver previa button outside the dialog and the dialog closes itself with Voltar a preencher" do
    get new_campaign_path
    open_buttons = css_select("button").select { |button| button.text.squish.include?("Ver prévia") }
    assert_equal 1, open_buttons.size
    open_button = open_buttons.first
    assert_equal "button", open_button["type"]
    assert_includes open_button["data-action"].to_s.split, "campaign-form#openPreview"
    assert_empty open_button.ancestors("dialog").to_a, "o botão que abre a folha não pode ficar dentro dela"
    assert_select "dialog.ui-stage button[type=button][data-action~=?]", "campaign-form#closePreview", text: /Voltar a preencher/
    assert_select 'button[data-action~="campaign-form#openPreview"] img[data-campaign-form-target="previewThumb"]', count: 1
  end

  test "a new campaign shows the placeholder offer, hides name, logo and photo and has no asterisk art" do
    get new_campaign_path
    assert_equal "Sua próxima grande oferta.", css_select('[data-campaign-form-target="previewOffer"]').first.text
    assert_select '[data-campaign-form-target="previewBusiness"][hidden]'
    assert_select '[data-campaign-form-target="previewLogo"][hidden]'
    assert_select '[data-campaign-form-target="previewPhoto"][hidden]'
    assert_select '[data-campaign-form-target="previewThumb"][hidden]'
    refute_includes response.body, "✳"
  end

  test "a saved campaign fills the offer, the name, the strip and its saved color from the server" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    get campaign_path(campaign)
    assert_equal campaign.display_offer, css_select('[data-campaign-form-target="previewOffer"]').first.text
    assert_select '[data-campaign-form-target="previewBusiness"]:not([hidden])', text: "Landel"
    assert_select '[data-campaign-form-target="previewCtaPanel"]:not([hidden])[style*="--campaign-cta-color: #6b21a8"]'
    assert_select '[data-campaign-form-target="previewCta"]', text: "Saiba mais no Instagram"
    assert_select '[data-campaign-form-target="previewContact"]', text: "@landel"
  end

  test "a blank name keeps the name target hidden and a saved logo shows in its place" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), business_name: ""))
    campaign.logo.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "logo.png", content_type: "image/png")
    get campaign_path(campaign)
    assert_select '[data-campaign-form-target="previewBusiness"][hidden]'
    assert_select %([data-campaign-form-target="previewLogo"]:not([hidden])[src="#{rails_blob_path(campaign.logo)}"])
  end

  test "without the strip the contact panel is hidden but still rendered for the chips to show again" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), show_cta: false, contact: "", call_to_action: ""))
    get campaign_path(campaign)
    assert_select '[data-campaign-form-target="previewCtaPanel"][hidden]', count: 1
  end

  test "the saved first photo is the phone photo and the thumbnail of the Ver previa button" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/demos/cafe-aurora.jpg"))), filename: "primeira.jpg", content_type: "image/jpeg")
    campaign.photos.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "segunda.png", content_type: "image/png")
    get campaign_path(campaign)
    first_path = rails_blob_path(campaign.product_photos.first)
    assert_select %([data-campaign-form-target="previewPhoto"]:not([hidden])[src="#{first_path}"])
    assert_select %([data-campaign-form-target="previewThumb"]:not([hidden])[src="#{first_path}"])
    refute_includes response.body, "✳"
  end

  test "a started checkout still renders the preview dialog and the Ver previa button on the last step" do
    order = orders(:b2b_pending)
    order.update!(stripe_session_id: "cs_preview_started")
    campaign = Campaign.create!(@attributes.merge(order: order))
    open_session = Stripe::Checkout::Session.construct_from(id: "cs_preview_started", status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/preview")
    Stripe::Checkout::Session.stub(:retrieve, open_session) do
      get campaign_path(campaign)
    end
    assert_response :success
    assert_select "form.ui-form dialog.ui-stage", count: 1
    assert_select 'button[data-action~="campaign-form#openPreview"]', count: 1
    assert_select '[data-campaign-form-target="previewOffer"]', count: 1
  end
end
