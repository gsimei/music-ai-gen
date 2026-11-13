require "test_helper"

# Casa do Criar (tarefa 3 do plano "caminho B"): raiz `.studio-home.criar` sem as classes
# legadas, cabeçalho, barra de passos, barra de ação e chips de identidade salva.
# O conteúdo de cada passo é tratado nas tarefas 4 a 7.
class CriarShellTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90, nesta terça", contact: "@pizzariadavila",
      call_to_action: "Peça pelo WhatsApp", style: "animado" }
  end

  test "the root is the criar shell without the legacy studio-app and campaign-app classes" do
    get new_campaign_path
    assert_response :success
    assert_select "div.studio-home.criar"
    assert_select ".studio-app", count: 0
    assert_select ".campaign-app", count: 0
    assert_select ".criar[data-step]", count: 1
  end

  test "the page keeps a single visually hidden h1 and the step titles stay h2" do
    get new_campaign_path
    assert_select "h1", count: 1
    assert_select ".criar h1.ui-sr-only", text: "Sua próxima campanha."
    assert_select ".criar h2"
  end

  test "the header offers the library, the create pill and sign out" do
    get new_campaign_path
    assert_select ".criar header.studio-app-header" do
      assert_select "a[href=?]", songs_path, text: "Minhas campanhas"
      assert_select "a.studio-header-create[href=?]", new_order_path, text: "Criar promoção"
      assert_select "button", text: "Sair"
    end
  end

  test "the form is a non turbo ui-form that starts at the first step" do
    get new_campaign_path
    assert_select 'form.ui-form[data-turbo="false"][data-campaign-form-initial-step-value="0"]'
    assert_select 'form.ui-form[data-controller~="campaign-form"]'
    assert_select 'div.studio-home.criar[data-step="1"]'
    assert_select "form.ui-form .ui-head"
  end

  test "the step bar is a nav with three segments and a one line label for step 1" do
    get new_campaign_path
    assert_select 'nav[aria-label="Etapas da campanha"]' do
      assert_select '[data-campaign-form-target="indicator"]', count: 3
    end
    indicators = css_select('nav[aria-label="Etapas da campanha"] [data-campaign-form-target="indicator"]')
    assert_equal [ true, false, false ], indicators.map { |item| item["aria-current"] == "step" }
    assert_select '[data-campaign-form-target="stepLabel"]', text: "Passo 1 de 3 · Sua promoção"
  end

  test "the action bar has a hidden back button, a continue button and exactly one submit" do
    get new_campaign_path
    assert_select "form.ui-form .ui-actionbar" do
      assert_select 'button[type="button"][data-campaign-form-target="back"][hidden]', text: /Voltar/
      assert_select 'button[type="button"][data-campaign-form-target="next"]', text: /Continuar/
    end
    assert_select "form.ui-form button[type=submit]", count: 1
    assert_select "form.ui-form input[type=submit]", count: 0
    assert_select "form.ui-form .ui-actionbar button[type=submit][data-campaign-form-target=submit]"
  end

  test "the submit button names the server price and the action" do
    get new_campaign_path
    price = ApplicationController.helpers.campaign_price
    assert_select "form.ui-form .ui-actionbar button[type=submit]", text: Regexp.new(Regexp.escape("Pagar #{price} e criar campanha"))
    assert_select "form.ui-form input[type=submit][value]", count: 0
  end

  test "the submit label follows the frozen order price" do
    order = orders(:b2b_pending)
    order.update!(price_cents: 3990, currency: "BRL")
    campaign = Campaign.create!(@attributes.merge(order: order))
    get campaign_path(campaign)
    assert_response :success
    assert_select "form.ui-form button[type=submit]", text: /Pagar R\$ 39,90 e criar campanha/
  end

  test "saved identities become chips with name and sound summary and mark the applied one" do
    user = users(:customer_b2b)
    vila = user.business_music_profiles.create!(business_name: "Pizzaria da Vila", musical_genre: "forro", vocal_gender: "female", style: "animado")
    cafe = user.business_music_profiles.create!(business_name: "Café Aurora", musical_genre: "pagode", vocal_gender: "male", style: "animado")
    get new_campaign_path
    [ vila, cafe ].each do |profile|
      assert_select ".criar a[href=?]", new_campaign_path(music_profile_id: profile.id) do |links|
        assert_includes links.first.text, profile.business_name
        assert_includes links.first.text, profile.sound_summary
        assert_nil links.first["aria-current"]
      end
    end
    assert_select ".criar a", text: "Começar sem identidade salva", count: 0

    get new_campaign_path(music_profile_id: vila.id)
    assert_response :success
    assert_select ".criar a[href=?][aria-current]", new_campaign_path(music_profile_id: vila.id)
    assert_select ".criar a[href=?][aria-current]", new_campaign_path(music_profile_id: cafe.id), count: 0
    assert_select ".criar a[href=?]", new_campaign_path, text: "Começar sem identidade salva"
  end

  test "a persisted campaign opens on the last step" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending)))
    get campaign_path(campaign)
    assert_response :success
    assert_select 'div.studio-home.criar[data-step="3"]'
    assert_select 'form.ui-form[data-campaign-form-initial-step-value="2"]'
    assert_select '[data-campaign-form-target="stepLabel"]', text: "Passo 3 de 3 · Conferir"
    indicators = css_select('nav[aria-label="Etapas da campanha"] [data-campaign-form-target="indicator"]')
    assert_equal 3, indicators.size
    assert_equal [ false, false, true ], indicators.map { |item| item["aria-current"] == "step" }
  end

  test "a payment failure also opens on the last step with the form filled" do
    order = orders(:b2b_pending)
    order.update!(status: "payment_failed")
    campaign = Campaign.create!(@attributes.merge(order: order))
    get campaign_path(campaign)
    assert_select 'div.studio-home.criar[data-step="3"]'
    assert_select '[data-campaign-form-target="stepLabel"]', text: "Passo 3 de 3 · Conferir"
    assert_select '[role="alert"]', text: /O pagamento não foi concluído/
    assert_select "textarea#campaign_offer", text: @attributes[:offer]
  end

  test "a started checkout keeps the three segments and shows only the last step label" do
    order = orders(:b2b_pending)
    order.update!(stripe_session_id: "cs_shell_started")
    campaign = Campaign.create!(@attributes.merge(order: order))
    open_session = Stripe::Checkout::Session.construct_from(id: "cs_shell_started", status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/shell")
    Stripe::Checkout::Session.stub(:retrieve, open_session) do
      get campaign_path(campaign)
    end
    assert_response :success
    assert_select 'div.studio-home.criar[data-step="3"]'
    assert_select '[data-campaign-form-target="stepLabel"]', text: "Passo 3 de 3 · Conferir"
    indicators = css_select('nav[aria-label="Etapas da campanha"] [data-campaign-form-target="indicator"]')
    assert_equal [ false, false, true ], indicators.map { |item| item["aria-current"] == "step" }
    assert_select "form.ui-form[action=?]", checkout_order_path(order)
    assert_select "form.ui-form button[type=submit]", count: 1
  end

  test "a rejected submission stays on the first step with the data filled" do
    assert_no_difference "Order.count" do
      post campaigns_path, params: { campaign: @attributes.merge(offer: "") }
    end
    assert_response :unprocessable_entity
    assert_select 'div.studio-home.criar[data-step="1"]'
    assert_select 'form.ui-form[data-campaign-form-initial-step-value="0"]'
    assert_select '[data-campaign-form-target="stepLabel"]', text: "Passo 1 de 3 · Sua promoção"
    assert_select '.criar [role="alert"]', text: /Oferta/
  end
end
