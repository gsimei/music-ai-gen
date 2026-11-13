require "application_system_test_case"
require "warden/test/helpers"

# Passo 3 do Criar no navegador (tarefa 7 do plano "caminho B"): ao sair do passo 2 o h2 "Confira e
# comece." recebe o foco, o resumo espelha o que foi digitado e escolhido (só o nome do ritmo), o
# "Editar" volta ao passo certo sem perder valores, o cartão de preço só aparece no passo 3 e, no
# celular, a barra de ação fixa não esconde o último conteúdo. O envio e a ida à letra ficam em
# merchant_checkout_test.rb. Nenhum teste aqui clica em "Pagar".
class CriarReviewStepSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  OFFER_LABEL = "Qual é a oferta ou novidade?".freeze
  CONTACT_LABEL = "WhatsApp, endereço ou @Instagram".freeze
  OFFER = "Café com pão a R$ 12 nesta terça.".freeze

  setup do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "leaving step 2 focuses the review heading, the summary mirrors the choices and the price card shows only here" do
    walk_to_review
    assert_selector ".ui-step:not([hidden]) h2:focus", text: "Confira e comece."
    assert_selector ".ui-step:not([hidden]) h2 em", text: "comece."
    assert_text "Depois do pagamento você revisa a letra e ouve duas versões de música."
    within('[data-summary="promotion"]') do
      assert_text "Café do Bairro"
      assert_text(/Café com pão a R\$[[:space:]]12 nesta terça\./)
      assert_text "Peça pelo WhatsApp · @cafedobairro"
    end
    within('[data-summary="sound"]') do
      assert_text "Forró · Voz feminina · Acolhedor"
      assert_no_text "alegre e versátil"
      assert_no_text "sanfona e alegria"
      assert_text "Cantada em português do Brasil"
    end
    within('[data-summary="photos"]') { assert_text "Sem fotos: criamos uma arte com a sua oferta." }
    within(".ui-price") do
      assert_text "Campanha completa"
      assert_text "R$ 29,90"
      assert_text "Até #{Campaigns::MusicRounds::LIMIT} rodadas"
      assert_text "Até #{BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :lyrics_regen_limit)} reescritas"
      assert_no_button
    end
    assert_text "Você seguirá para o pagamento seguro pelo Stripe. A criação começa após a confirmação."
    assert_selector ".ui-actionbar button[type=submit]", text: "Pagar R$ 29,90 e criar campanha"
    assert_equal 1, page.evaluate_script("document.querySelectorAll('form.ui-form button[type=submit]').length")
    assert_fits_horizontally
    assert_no_javascript_errors
  end

  test "the summary shows the first photo as a thumbnail and counts them" do
    visit new_campaign_path
    fill_first_step
    attach_file "Fotos do produto ou do negócio (opcional)", Rails.root.join("public/icon.png"), make_visible: true
    assert_selector ".ui-slots figure.ui-slot img", count: 1
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    within('[data-summary="photos"]') do
      assert_selector "img", count: 1
      assert_text "1 foto"
      assert_no_text "Sem fotos"
    end
    assert_no_javascript_errors
  end

  test "Editar goes back to its step with the values kept, and the edited text reaches the summary" do
    walk_to_review

    within('[data-summary="promotion"]') { click_button "Editar" }
    assert_selector ".criar[data-step='1']"
    assert_selector ".ui-step:not([hidden]) h2:focus"
    wait_for_head_at_top
    assert_field OFFER_LABEL, with: OFFER
    assert_field "Nome do seu negócio", with: "Café do Bairro"
    fill_in OFFER_LABEL, with: "Bolo de fubá por R$ 8 hoje."
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    assert_equal "forro", checked_genre, "voltar não pode perder o ritmo escolhido"
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    within('[data-summary="promotion"]') { assert_text(/Bolo de fubá por R\$[[:space:]]8 hoje\./) }

    within('[data-summary="sound"]') { click_button "Editar" }
    assert_selector ".criar[data-step='2']"
    assert_selector ".ui-step:not([hidden]) h2:focus", text: "Como sua promoção deve soar?"
    assert_equal "forro", checked_genre
    find("label.ui-tile", text: /\APagode/).click
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    within('[data-summary="sound"]') { assert_text "Pagode · Voz feminina · Acolhedor" }

    within('[data-summary="photos"]') { click_button "Editar" }
    assert_selector ".criar[data-step='1']"
    assert_selector ".ui-step:not([hidden]) h2:focus"
    assert_no_javascript_errors
  end

  test "blank name and no strip are reflected in the summary" do
    visit new_campaign_path
    fill_in OFFER_LABEL, with: OFFER
    find("label", text: "Sem faixa de contato").click
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    within('[data-summary="promotion"]') do
      assert_text "Sem faixa de contato"
      assert_no_text "Peça pelo WhatsApp"
      assert_no_selector '[data-campaign-form-target="summaryBusiness"]'
    end
    assert_no_javascript_errors
  end

  test "on a 390 px phone the action bar is fixed, nothing hides behind it and the page does not scroll sideways" do
    walk_to_review(width: 390, height: 844, mobile: true)
    assert_selector ".ui-step:not([hidden]) h2:focus", text: "Confira e comece."
    assert_equal "fixed", page.evaluate_script("getComputedStyle(document.querySelector('.ui-actionbar')).position")
    bar = page.evaluate_script("(() => { const r = document.querySelector('.ui-actionbar').getBoundingClientRect(); return { top: r.top, bottom: r.bottom, height: r.height } })()")
    assert_in_delta page.evaluate_script("window.innerHeight"), bar["bottom"], 1.5, "a barra de ação encosta no rodapé da janela"
    assert_selector ".ui-price"
    assert_selector ".ui-summary"
    assert_fits_horizontally

    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    sleep 0.3
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const bar = document.querySelector(".ui-actionbar").getBoundingClientRect()
        const float = Array.from(document.querySelectorAll(".ui-float")).find(node => node.checkVisibility())
        const limit = Math.min(bar.top, float ? float.getBoundingClientRect().top : Infinity)
        const bottoms = Array.from(document.querySelectorAll(".criar *")).filter(node => {
          if (node.closest(".ui-actionbar, dialog, .ui-sr-only, header")) return false
          if (node.children.length > 0 || !node.checkVisibility()) return false
          const rect = node.getBoundingClientRect()
          return rect.width > 0 && rect.height > 0 && getComputedStyle(node).position !== "fixed"
        }).map(node => node.getBoundingClientRect().bottom)
        return { limit, lowest: Math.max(...bottoms) }
      })()
    JS
    assert_operator metrics["lowest"], :<=, metrics["limit"] + 1, "o último conteúdo (#{metrics['lowest']}px) fica atrás da barra de ação (#{metrics['limit']}px)"
    assert_no_javascript_errors
  end

  private

  # Nome, oferta e contato do passo 1; Forró, voz feminina e clima acolhedor no 2. Confere, a cada passo,
  # que o cartão de preço só aparece no último.
  def walk_to_review(width: 1280, height: 900, mobile: false)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: mobile)
    visit new_campaign_path
    assert_selector ".criar[data-step='1']"
    assert_no_selector ".ui-price"
    fill_first_step
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    assert_no_selector ".ui-price"
    click_centered find("label.ui-tile", text: /\AForró/)
    click_centered find("label", text: "Voz feminina")
    click_centered find("label.ui-chip", text: "Acolhedor")
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    assert_selector ".ui-price"
  end

  def fill_first_step
    fill_in "Nome do seu negócio", with: "Café do Bairro"
    fill_in OFFER_LABEL, with: OFFER
    fill_in CONTACT_LABEL, with: "@cafedobairro"
  end

  def click_centered(node)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", node)
    node.click
  end

  def checked_genre
    page.evaluate_script('document.querySelector(\'input[name="campaign[musical_genre]"]:checked\').value')
  end

  def assert_fits_horizontally
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "A página rola na horizontal"
  end

  def wait_for_head_at_top
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    top = head_top
    until top.between?(-2, 24)
      flunk "O .ui-head deveria estar no topo da janela depois do Editar, mas está a #{top}px" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
      top = head_top
    end
  end

  def head_top
    page.evaluate_script("document.querySelector('.ui-head').getBoundingClientRect().top")
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
