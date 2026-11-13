require "application_system_test_case"
require "warden/test/helpers"

# Passo 2 do Criar no navegador (tarefa 6 do plano "caminho B"): tiles, voz, clima, detalhes e o
# player da marca. Regra de ouro: nenhum som toca sem clique no botão tocar/pausar do cartão. Os
# exemplos são arquivos estáticos de public/demos/genres/; a Mureka nunca é chamada (a rede externa
# está bloqueada pelo WebMock em ApplicationSystemTestCase).
class CriarSoundStepSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  AUDIO = '[data-genre-preview-target="player"]'.freeze
  TOGGLE = '[data-genre-preview-target="toggle"]'.freeze
  CURRENT = '[data-genre-preview-target="current"]'.freeze
  DURATION = '[data-genre-preview-target="duration"]'.freeze
  NAME = '[data-genre-preview-target="name"]'.freeze
  DESCRIPTION = '[data-genre-preview-target="description"]'.freeze
  HINT = '[data-genre-preview-target="hint"]'.freeze
  ERROR = '[data-genre-preview-target="error"]'.freeze
  DIRECTION = '[data-campaign-form-target="direction"]'.freeze
  DETAILS_BUTTON = ".ui-step:not([hidden]) button[aria-expanded][aria-controls]".freeze

  setup do
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
    Warden.test_reset!
  end

  test "picking a tile by click swaps the sample, names the card and never plays" do
    open_step_two
    assert_audio_src "/demos/genres/pop-v1.mp3"
    assert_selector NAME, text: "Pop"
    assert_selector DESCRIPTION, text: "alegre e versátil"
    assert_selector DURATION, text: "0:12"
    assert_selector CURRENT, text: "0:00"
    assert_equal "Tocar exemplo", find(TOGGLE)["aria-label"]
    assert audio_value("paused"), "ao abrir o passo o som não toca"

    [ [ "Forró", "forro", "sanfona e alegria" ], [ "Pagode", "pagode", "cavaquinho e balanço" ], [ "Natal", "natal", "sinos e clima de festa" ] ].each do |name, key, description|
      click_centered tile(name)
      assert_audio_src "/demos/genres/#{key}-v1.mp3"
      assert_selector NAME, text: name
      assert_selector DESCRIPTION, text: description
      assert audio_value("paused"), "escolher #{name} não pode tocar"
      assert_equal "Tocar exemplo", find(TOGGLE)["aria-label"]
    end
    assert_equal 0, audio_value("played.length"), "nenhum trecho foi reproduzido: o cartão só toca com clique no botão"
    assert_no_javascript_errors
  end

  test "picking a tile with the arrow keys swaps the sample, keeps it silent and shows a 3px focus ring on the tile" do
    open_step_two
    assert_audio_src "/demos/genres/pop-v1.mp3"
    page.execute_script("document.querySelector('input[name=\"campaign[musical_genre]\"]:checked').focus()")
    page.driver.browser.action.send_keys(:arrow_right).perform
    assert_equal "natal", checked_genre
    assert_audio_src "/demos/genres/natal-v1.mp3"
    assert audio_value("paused")
    page.driver.browser.action.send_keys(:arrow_left).perform
    assert_equal "pop", checked_genre
    assert_audio_src "/demos/genres/pop-v1.mp3"
    assert_equal 0, audio_value("played.length"), "navegar por teclado não pode disparar som"
    ring = page.evaluate_script(<<~JS)
      (() => {
        const label = document.querySelector('input[name="campaign[musical_genre]"]:checked').closest("label")
        const style = getComputedStyle(label)
        return { width: parseFloat(style.outlineWidth), style: style.outlineStyle }
      })()
    JS
    assert_operator ring["width"], :>=, 3, "o foco por teclado precisa de um anel de 3 px no tile"
    assert_not_equal "none", ring["style"]
    assert_no_javascript_errors
  end

  test "the play button starts the sample, the clock moves, pause stops it and the label follows" do
    open_step_two
    assert_audio_src "/demos/genres/pop-v1.mp3"
    find(TOGGLE).click
    assert_selector TOGGLE + '[aria-label="Pausar exemplo"]'
    assert_equal false, audio_value("paused")
    assert_selector CURRENT, text: /\A0:0[1-9]\z/, wait: 12
    find(TOGGLE).click
    assert_selector TOGGLE + '[aria-label="Tocar exemplo"]'
    assert audio_value("paused")
    frozen = find(CURRENT).text
    stopped_at = audio_value("currentTime")
    sleep 0.7
    assert_equal frozen, find(CURRENT).text
    assert_in_delta stopped_at, audio_value("currentTime"), 0.05
    assert_no_javascript_errors
  end

  test "changing the rhythm while playing stops the sound and resets the clock" do
    open_step_two
    find(TOGGLE).click
    assert_selector CURRENT, text: /\A0:0[1-9]\z/, wait: 12
    click_centered tile("Sertanejo")
    assert_audio_src "/demos/genres/sertanejo-v1.mp3"
    assert audio_value("paused"), "trocar de ritmo para o som"
    assert_selector CURRENT, text: "0:00"
    assert_selector TOGGLE + '[aria-label="Tocar exemplo"]'
    assert_equal 0, audio_value("currentTime")
    assert_no_javascript_errors
  end

  test "leaving the step pauses the sample and the button is back to play when returning" do
    open_step_two
    find(TOGGLE).click
    assert_selector TOGGLE + '[aria-label="Pausar exemplo"]'
    assert_selector CURRENT, text: /\A0:0[1-9]\z/, wait: 12
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    assert audio_value("paused"), "trocar de passo pausa o exemplo"
    click_button "Voltar"
    assert_selector ".criar[data-step='2']"
    assert_selector TOGGLE + '[aria-label="Tocar exemplo"]'
    assert_no_javascript_errors
  end

  test "choose for me shows the hint in place of the play button and loads no sample" do
    open_step_two
    click_centered tile("Escolher por mim")
    assert_selector HINT, text: "Escolha um ritmo para ouvir um exemplo antes de decidir."
    assert_no_selector TOGGLE
    assert_selector NAME, text: "Escolher por mim"
    refute page.evaluate_script("document.querySelector('#{AUDIO}').hasAttribute('src')"), "sem exemplo, sem src"
    click_centered tile("Pop")
    assert_selector TOGGLE
    assert_no_selector HINT
    assert_no_javascript_errors
  end

  test "a playback error shows the message with a retry that hides it again" do
    open_step_two
    assert_audio_src "/demos/genres/pop-v1.mp3"
    assert_no_selector ERROR
    page.execute_script("document.querySelector('#{AUDIO}').dispatchEvent(new Event('error'))")
    assert_selector ERROR, text: "Não foi possível tocar o exemplo"
    assert_selector "#{ERROR} button", text: "Tentar de novo"
    find("#{ERROR} button", text: "Tentar de novo").click
    assert_no_selector ERROR
    page.execute_script("document.querySelector('#{AUDIO}').pause()")
    assert_no_javascript_errors
  end

  test "the wave is still while paused, moves while playing and stays still with reduced motion" do
    open_step_two
    assert_equal 0, running_bars, "com o áudio pausado a onda fica parada"
    find(TOGGLE).click
    assert_selector TOGGLE + '[aria-label="Pausar exemplo"]'
    assert_operator running_bars, :>, 0, "tocando, as barras animam"
    find(TOGGLE).click
    assert_selector TOGGLE + '[aria-label="Tocar exemplo"]'
    assert_equal 0, running_bars, "pausou, a onda para"

    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    find(TOGGLE).click
    assert_selector TOGGLE + '[aria-label="Pausar exemplo"]'
    assert_equal 0, running_bars, "prefers-reduced-motion: reduce mantém a onda parada mesmo tocando"
    find(TOGGLE).click
    assert_no_javascript_errors
  end

  test "on desktop the tiles make four columns and the card sits to their right, with big targets and token colors" do
    open_step_two(width: 1280, height: 900)
    assert_selector "label.ui-tile", count: Campaign::GENRES.size
    assert_selector ".ui-player #{TOGGLE}"
    layout = page.evaluate_script(<<~JS)
      (() => {
        const rect = el => { const r = el.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width, height: r.height } }
        const tiles = Array.from(document.querySelectorAll("label.ui-tile")).map(rect)
        return { lefts: [...new Set(tiles.map(t => Math.round(t.left)))], tilesRight: Math.max(...tiles.map(t => t.right)),
                 tilesTop: Math.min(...tiles.map(t => t.top)), tilesBottom: Math.max(...tiles.map(t => t.bottom)),
                 player: rect(document.querySelector(".ui-player")), toggle: rect(document.querySelector('#{TOGGLE}')),
                 count: tiles.length }
      })()
    JS
    assert_equal Campaign::GENRES.size, layout["count"]
    assert_equal 4, layout["lefts"].size, "4 colunas de tiles no desktop"
    assert_operator layout["player"]["left"], :>=, layout["tilesRight"] - 1, "o cartão fica à direita dos tiles"
    assert_operator layout["player"]["top"], :<, layout["tilesBottom"]
    assert_operator layout["toggle"]["width"], :>=, 44
    assert_operator layout["toggle"]["height"], :>=, 44
    assert_selector "label.ui-chip input[name='campaign[style]']", visible: :all, count: Campaign::STYLES.size
    assert_equal token_color("--jp-forest"), checked_background("input[name='campaign[musical_genre]']:checked", "label.ui-tile"), "tile selecionado = fundo floresta"
    refute_equal token_color("--jp-forest"), unchecked_background("input[name='campaign[musical_genre]']", "label.ui-tile")
    assert_equal token_color("--jp-lime"), checked_background("input[name='campaign[style]']:checked", "label.ui-chip"), "clima selecionado = fundo lime"
    assert_no_javascript_errors
  end

  test "on a 390 px phone the tiles make two columns, the card sits between the last tile and the voice, nothing overflows" do
    open_step_two(width: 390, height: 844, mobile: true)
    assert_selector "label.ui-tile", count: Campaign::GENRES.size
    assert_selector ".ui-seg"
    assert_selector ".ui-player #{TOGGLE}"
    layout = page.evaluate_script(<<~JS)
      (() => {
        const rect = el => { const r = el.getBoundingClientRect(); return { left: r.left, right: r.right, top: r.top + window.scrollY, bottom: r.bottom + window.scrollY, width: r.width, height: r.height } }
        const tiles = Array.from(document.querySelectorAll("label.ui-tile")).map(rect)
        const voice = document.querySelector(".ui-seg").closest("fieldset")
        return { lefts: [...new Set(tiles.map(t => Math.round(t.left)))], lastBottom: Math.max(...tiles.map(t => t.bottom)),
                 player: rect(document.querySelector(".ui-player")), voice: rect(voice), toggle: rect(document.querySelector('#{TOGGLE}')),
                 fits: document.documentElement.scrollWidth <= window.innerWidth }
      })()
    JS
    assert_equal 2, layout["lefts"].size, "2 colunas de tiles no celular"
    assert_operator layout["player"]["top"], :>=, layout["lastBottom"] - 1, "o cartão fica abaixo do último tile"
    assert_operator layout["voice"]["top"], :>=, layout["player"]["bottom"] - 1, "a voz vem depois do cartão"
    assert_operator layout["toggle"]["width"], :>=, 44
    assert_operator layout["toggle"]["height"], :>=, 44
    assert layout["fits"], "sem rolagem horizontal no passo 2 em 390 px"
    assert_no_javascript_errors
  end

  test "the plus details button opens and closes the notes field" do
    open_step_two
    assert_selector DETAILS_BUTTON + '[aria-expanded="false"]'
    assert_no_field "campaign_music_notes"
    find(DETAILS_BUTTON).click
    assert_selector DETAILS_BUTTON + '[aria-expanded="true"]'
    assert_field "campaign_music_notes"
    fill_in "campaign_music_notes", with: "Sanfona em destaque"
    find(DETAILS_BUTTON).click
    assert_selector DETAILS_BUTTON + '[aria-expanded="false"]'
    assert_no_field "campaign_music_notes"
    find(DETAILS_BUTTON).click
    assert_field "campaign_music_notes", with: "Sanfona em destaque"
    assert_no_javascript_errors
  end

  test "Sua direção follows the choices live" do
    open_step_two
    assert_direction "Pop", "Escolher por mim", "Animado"
    click_centered tile("Sertanejo")
    click_centered find("label", text: "Voz masculina")
    click_centered find("label.ui-chip", text: "Marcante")
    assert_direction "Sertanejo", "Voz masculina", "Marcante"
    assert_no_javascript_errors
  end

  test "the chosen sound is saved with the campaign" do
    open_step_two
    click_centered tile("Forró")
    click_centered find("label", text: "Voz feminina")
    click_centered find("label.ui-chip", text: "Acolhedor")
    find(DETAILS_BUTTON).click
    fill_in "campaign_music_notes", with: "Sanfona em destaque"
    click_button "Continuar"
    assert_selector ".criar[data-step='3']"
    click_button "Pagar R$ 29,90"
    assert_text "Sua campanha está salva"
    campaign = Campaign.last
    assert_equal [ "forro", "female", "acolhedor", "Sanfona em destaque" ], campaign.attributes.values_at("musical_genre", "vocal_gender", "style", "music_notes")
    assert_no_javascript_errors
  end

  private

  def open_step_two(width: 1280, height: 900, mobile: false)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: mobile)
    visit new_campaign_path
    fill_in "Qual é a oferta ou novidade?", with: "Pizza em dobro na terça"
    fill_in "WhatsApp, endereço ou @Instagram", with: "@pizzariadavila"
    click_button "Continuar"
    assert_selector ".criar[data-step='2']"
  end

  def tile(name)
    find("label.ui-tile", text: /\A#{Regexp.escape(name)}/)
  end

  # O rádio de um chip/tile é recortado; o clique vai no label, já no meio da janela para a barra de ação não interceptar.
  def click_centered(node)
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", node)
    node.click
  end

  def audio_value(expression)
    page.evaluate_script("document.querySelector('#{AUDIO}').#{expression}")
  end

  def assert_audio_src(path)
    assert_selector %(#{AUDIO}[src$="#{path}"]), visible: :all
  end

  def checked_genre
    page.evaluate_script('document.querySelector(\'input[name="campaign[musical_genre]"]:checked\').value')
  end

  def running_bars
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll('[data-genre-preview-target="wave"] > *')).filter(bar => {
        const style = getComputedStyle(bar)
        return style.animationName !== "none" && style.animationPlayState === "running"
      }).length
    JS
  end

  def token_color(token)
    page.evaluate_script(<<~JS)
      (() => { const probe = document.createElement("i"); probe.style.color = "var(#{token})"; document.body.append(probe)
               const color = getComputedStyle(probe).color; probe.remove(); return color })()
    JS
  end

  def checked_background(input_selector, label_selector)
    page.evaluate_script("getComputedStyle(document.querySelector(\"#{input_selector}\").closest(\"#{label_selector}\")).backgroundColor")
  end

  def unchecked_background(input_selector, label_selector)
    page.evaluate_script("getComputedStyle(document.querySelector(\"#{input_selector}:not(:checked)\").closest(\"#{label_selector}\")).backgroundColor")
  end

  def assert_direction(genre, voice, climate)
    [ genre, voice, climate ].each_with_index do |text, index|
      assert_selector "#{DIRECTION} li:nth-child(#{index + 1})", text: text, exact_text: true
    end
    assert_selector "#{DIRECTION} li", count: 3
  end

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action|violates.*Content Security Policy/i) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
