require "application_system_test_case"
require "warden/test/helpers"

# Prévia em arco e folha "Ver prévia" (tarefa 5 do plano "caminho B"). Um único <dialog class="ui-stage">:
# aberto e fixo na coluna da direita a partir de 960 px (só no passo 1) e fechado no celular, onde o
# botão "Ver prévia" o abre como modal nos passos 1 e 3.
class CriarPreviewSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  STAGE = "dialog.ui-stage".freeze

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "on desktop the dialog is open, sticky and stays in the window while the form scrolls" do
    resize(1280, 600, mobile: false)
    visit new_campaign_path
    assert_selector ".criar[data-step='1']"
    assert_selector "#{STAGE}[open]"
    assert_no_button "Ver prévia"
    assert sticky_in_ancestry?, "o dialog (ou o contêiner da coluna) deve ser position: sticky"
    assert_operator page.evaluate_script("document.documentElement.scrollHeight"), :>, page.evaluate_script("window.innerHeight"),
      "o passo 1 precisa rolar para provar que a prévia acompanha"
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    rect = page.evaluate_script("(() => { const r = document.querySelector('#{STAGE}').getBoundingClientRect(); return { top: r.top, bottom: r.bottom, height: window.innerHeight } })()")
    assert_operator rect["bottom"], :>, 100, "a prévia saiu da janela: #{rect.inspect}"
    assert_operator rect["top"], :<, rect["height"] - 100, "a prévia saiu da janela: #{rect.inspect}"
    assert_no_javascript_errors
  end

  test "on desktop the preview follows typing, the chosen strip and the first photo" do
    resize(1280, 800, mobile: false)
    visit new_campaign_path
    assert_selector "#{STAGE}[open]"
    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    within(STAGE) { assert_selector '[data-campaign-form-target="previewOffer"]', text: "Pizza em dobro na terça" }
    fill_in "Nome do seu negócio", with: "Pizzaria da Vila"
    within(STAGE) { assert_selector '[data-campaign-form-target="previewBusiness"]', text: "Pizzaria da Vila" }
    fill_in "WhatsApp, endereço ou @Instagram", with: "@pizzariadavila"
    within(STAGE) { assert_selector '[data-campaign-form-target="previewContact"]', text: "@pizzariadavila" }
    find("label", text: "Sem faixa de contato").click
    within(STAGE) { assert_no_selector '[data-campaign-form-target="previewCtaPanel"]' }
    find("label", text: "Peça pelo WhatsApp").click
    within(STAGE) { assert_selector '[data-campaign-form-target="previewCtaPanel"]' }
    within(STAGE) { assert_no_selector '[data-campaign-form-target="previewPhoto"]' }
    attach_file "Fotos do produto ou do negócio (opcional)", Rails.root.join("public/icon.png"), make_visible: true
    within(STAGE) { assert_selector '[data-campaign-form-target="previewPhoto"][src^="blob:"]' }
    assert_no_javascript_errors
  end

  test "on desktop the preview column belongs to step 1 only" do
    resize(1280, 800, mobile: false)
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    fill_in "WhatsApp, endereço ou @Instagram", with: "@pizzariadavila"
    assert_selector "#{STAGE}[open]"
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    assert_no_selector STAGE
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    assert_no_selector STAGE
    click_button "Voltar"
    click_button "Voltar"
    assert_selector ".criar[data-step='1']"
    assert_selector STAGE
    assert_no_javascript_errors
  end

  test "on a phone the dialog is closed and gone from the page, and Ver previa shows only on steps 1 and 3" do
    resize(390, 844, mobile: true)
    visit new_campaign_path
    assert_selector ".criar[data-step='1']"
    assert_selector "#{STAGE}", visible: :all
    refute page.evaluate_script("document.querySelector('#{STAGE}').open")
    assert_no_selector STAGE
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('#{STAGE}')).display")
    assert_button "Ver prévia"
    assert fits_horizontally?

    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    fill_in "WhatsApp, endereço ou @Instagram", with: "@pizzariadavila"
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    assert_no_button "Ver prévia"
    assert fits_horizontally?
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    assert_button "Ver prévia"
    assert fits_horizontally?
    assert_no_javascript_errors
  end

  test "on a phone Ver previa opens a modal sheet with the typed offer and both Voltar a preencher and Esc close it and return focus" do
    resize(390, 844, mobile: true)
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Casa com 03 quartos\nR$ 750.000"
    fill_in "Nome do seu negócio", with: "Landel"

    click_button "Ver prévia"
    assert_selector "#{STAGE}[open]"
    assert page.evaluate_script("document.querySelector('#{STAGE}').matches(':modal')"), "no celular a prévia abre com showModal()"
    within(STAGE) do
      assert_selector '[data-campaign-form-target="previewOffer"]', text: /Casa com 03 quartos/
      assert_selector '[data-campaign-form-target="previewBusiness"]', text: "Landel"
    end
    click_button "Voltar a preencher"
    assert_no_selector "#{STAGE}[open]"
    assert_focus_on_open_button

    click_button "Ver prévia"
    assert_selector "#{STAGE}[open]"
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector "#{STAGE}[open]"
    assert_focus_on_open_button
    assert fits_horizontally?
    assert_no_javascript_errors
  end

  test "the sheet also opens on the last step" do
    resize(390, 844, mobile: true)
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    fill_in "WhatsApp, endereço ou @Instagram", with: "@pizzariadavila"
    2.times { click_button "Continuar" }
    assert_selector ".criar[data-step='3']"
    click_button "Ver prévia"
    assert_selector "#{STAGE}[open]"
    within(STAGE) { assert_selector '[data-campaign-form-target="previewOffer"]', text: "Pizza em dobro na terça" }
    click_button "Voltar a preencher"
    assert_no_selector "#{STAGE}[open]"
    assert_no_javascript_errors
  end

  test "resizing from a phone to desktop opens the dialog in place and back to a phone closes it" do
    resize(390, 844, mobile: true)
    visit new_campaign_path
    assert_selector ".criar[data-step='1']"
    assert_no_selector STAGE
    resize(1280, 800, mobile: false)
    assert_selector "#{STAGE}[open]"
    assert_no_button "Ver prévia"
    resize(390, 844, mobile: true)
    assert_no_selector "#{STAGE}[open]"
    assert_no_selector STAGE
    assert_button "Ver prévia"
    assert_no_javascript_errors
  end

  test "a photo shows as the thumbnail of the Ver previa button on a phone" do
    resize(390, 844, mobile: true)
    visit new_campaign_path
    assert_no_selector '[data-campaign-form-target="previewThumb"]'
    attach_file "Fotos do produto ou do negócio (opcional)", Rails.root.join("public/icon.png"), make_visible: true
    assert_selector 'button[data-action~="campaign-form#openPreview"] img[data-campaign-form-target="previewThumb"][src^="blob:"]'
    assert_no_javascript_errors
  end

  private

  def resize(width, height, mobile:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: mobile)
  end

  def sticky_in_ancestry?
    page.evaluate_script(<<~JS)
      (() => {
        for (let node = document.querySelector('#{STAGE}'); node && node !== document.body; node = node.parentElement) {
          if (getComputedStyle(node).position === "sticky") return true
        }
        return false
      })()
    JS
  end

  def fits_horizontally?
    page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
  end

  def assert_focus_on_open_button
    focused = page.evaluate_script("document.activeElement && document.activeElement.textContent.includes('Ver prévia')")
    assert focused, "ao fechar a folha o foco volta ao botão Ver prévia"
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
