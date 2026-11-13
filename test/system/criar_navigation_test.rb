require "application_system_test_case"
require "warden/test/helpers"

# Navegação entre passos do Criar (tarefa 3 do plano "caminho B"): ao trocar de passo a página
# volta ao topo do formulário (`.ui-head`), o foco vai para o h2 do passo, a etiqueta
# "Passo N de 3 · Título" cabe em uma linha e nada estoura na horizontal.
class CriarNavigationTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  STEP_LABELS = { 1 => "Passo 1 de 3 · Sua promoção", 2 => "Passo 2 de 3 · Sua música", 3 => "Passo 3 de 3 · Conferir" }.freeze

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    Warden.test_reset!
  end

  test "continue and back return to the form head and focus the step heading on desktop" do
    resize(1280, 640, mobile: false)
    walk_first_two_steps
  end

  test "continue and back return to the form head and focus the step heading on a 390 px phone" do
    resize(390, 640, mobile: true)
    walk_first_two_steps(horizontal_scroll_check: true)
  end

  test "reduced motion changes steps without smooth scrolling" do
    resize(1280, 640, mobile: false)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    fill_first_step
    scroll_to_bottom
    install_scroll_spy
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
    wait_for_head_at_top
    behaviors = page.evaluate_script("window.__scrollBehaviors")
    refute_includes behaviors, "smooth", "Com prefers-reduced-motion: reduce a rolagem não pode ser suave"
    assert_no_javascript_errors
  end

  private

  def walk_first_two_steps(horizontal_scroll_check: false)
    fill_first_step
    assert_equal STEP_LABELS.fetch(1), find('[data-campaign-form-target="stepLabel"]').text
    assert_label_on_one_line
    assert_fits_horizontally if horizontal_scroll_check
    scroll_to_bottom
    assert_operator scroll_y, :>, 0, "o passo 1 precisa rolar para o teste provar que a página volta ao topo"
    click_button "Continuar"
    assert_step 2
    assert_fits_horizontally if horizontal_scroll_check
    scroll_to_bottom
    click_button "Voltar"
    assert_step 1
    assert_fits_horizontally if horizontal_scroll_check
    click_button "Continuar"
    assert_step 2
    assert_no_javascript_errors
  end

  def fill_first_step
    visit new_campaign_path
    assert_selector ".criar[data-step='1']"
    find("#campaign_offer").set("Pizza em dobro na terça")
    find("#campaign_contact").set("@pizzariadavila")
  end

  def assert_step(number)
    assert_selector ".criar[data-step='#{number}']"
    wait_for_head_at_top
    assert_equal STEP_LABELS.fetch(number), find('[data-campaign-form-target="stepLabel"]').text
    focus = page.evaluate_script(<<~JS)
      (() => {
        const active = document.activeElement
        return { tag: active.tagName, inVisibleStep: !!active.closest('[data-campaign-form-target="step"]:not([hidden])') }
      })()
    JS
    assert_equal "H2", focus["tag"], "o foco deve ir para o h2 do passo #{number}"
    assert focus["inVisibleStep"], "o h2 focado deve pertencer ao passo visível"
    assert_label_on_one_line
  end

  def assert_label_on_one_line
    metrics = page.evaluate_script(<<~JS)
      (() => {
        const label = document.querySelector('[data-campaign-form-target="stepLabel"]')
        const style = getComputedStyle(label)
        const lineHeight = parseFloat(style.lineHeight) || parseFloat(style.fontSize) * 1.2
        const padding = parseFloat(style.paddingTop) + parseFloat(style.paddingBottom)
        return { content: label.clientHeight - padding, lineHeight: lineHeight, overflow: label.scrollWidth - label.clientWidth, fontSize: parseFloat(style.fontSize) }
      })()
    JS
    assert_operator metrics["content"], :<=, metrics["lineHeight"] * 1.3, "A etiqueta de passo quebrou em mais de uma linha: #{metrics.inspect}"
    assert_operator metrics["overflow"], :<=, 1, "A etiqueta de passo estoura a própria largura: #{metrics.inspect}"
    assert_operator metrics["fontSize"], :>=, 13, "A etiqueta de passo tem menos de 13 px"
  end

  def assert_fits_horizontally
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "A página rola na horizontal"
  end

  def wait_for_head_at_top
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + Capybara.default_max_wait_time
    top = head_top
    until top.between?(-2, 24)
      flunk "O .ui-head deveria estar no topo da janela depois de trocar de passo, mas está a #{top}px (scrollY #{scroll_y})" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
      top = head_top
    end
    top
  end

  def head_top
    page.evaluate_script("document.querySelector('.ui-head').getBoundingClientRect().top")
  end

  def scroll_y
    page.evaluate_script("window.scrollY")
  end

  def scroll_to_bottom
    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
  end

  def install_scroll_spy
    page.execute_script(<<~JS)
      window.__scrollBehaviors = []
      const record = (options) => { if (options && typeof options === "object" && options.behavior) window.__scrollBehaviors.push(options.behavior) }
      const wrap = (owner, name) => {
        const original = owner[name]
        owner[name] = function (options) { record(options); return original.apply(this, arguments) }
      }
      wrap(Element.prototype, "scrollIntoView")
      wrap(window, "scrollTo")
      wrap(window, "scroll")
    JS
  end

  def resize(width, height, mobile:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: mobile)
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
