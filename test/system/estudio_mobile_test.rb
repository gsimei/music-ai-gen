require "application_system_test_case"
require "warden/test/helpers"

# Estúdio no celular (RF 5): em 375 × 812, nas três fases, a página não rola na horizontal, o botão principal da fase
# fica na barra de ação fixa (sem nada por cima) e o último campo do "Quero mudar algo" aberto não fica atrás da barra
# depois de scrollIntoView, porque html:has(.estudio) tem scroll-padding-bottom.
class EstudioMobileSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "phase 1 keeps the approve button in the fixed bar on a 375 px phone (RF 5)" do
    order = orders(:b2b_lyrics_ready)
    Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false).sync_briefing!
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Revise a letra."
    assert_mobile_phase "Aprovar letra e ouvir 2 versões", "#lyrics-changes"
  end

  test "phase 2 keeps the pick button in the fixed bar on a 375 px phone (RF 5)" do
    order = orders(:b2b_preview_ready)
    Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false).sync_briefing!
    order.all_music_assets.each { |asset| prepare_sample(asset) }
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Escolha a sua versão."
    assert_mobile_phase "Usar a Versão A e montar o vídeo", "#music-changes"
  end

  test "phase 3 keeps Gerar meu vídeo in the fixed bar and opens the preview as a sheet on a 375 px phone (RF 5)" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false)
    campaign.update!(selected_music_asset: order_assets(:music_variant_a))
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Monte o seu vídeo."
    assert_mobile_phase "Gerar meu vídeo", "#video-changes"

    assert_no_selector ".ui-stage" # fechada no celular: a prévia só abre pelo botão
    click_button "Ver prévia"
    assert_selector "dialog.ui-stage[open]", text: "Café por R$ 12"
    assert_fits_horizontally
    click_button "Voltar a montar"
    assert_no_selector ".ui-stage"
    assert_equal "Ver prévia", page.evaluate_script("document.activeElement.textContent.trim()"), "o foco volta para quem abriu a folha"
    assert_no_studio_errors
  end

  test "a broadcast while the Ver prévia sheet is open keeps the sheet (M10)" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false)
    campaign.update!(selected_music_asset: order_assets(:music_variant_a))
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Monte o seu vídeo."
    # Controle: com a folha fechada, o broadcast troca o painel.
    page.execute_script("document.getElementById('chat-lyrics-panel').dataset.sentinel = 'old'")
    OrderChatBroadcaster.call(order)
    assert_no_selector "#chat-lyrics-panel[data-sentinel]"
    # Conta os broadcasts do painel que chegaram e foram barrados (o guard do creative-editor roda antes deste ouvinte).
    page.execute_script(<<~JS)
      document.addEventListener("turbo:before-stream-render", event => {
        if (event.target.getAttribute("target") === "chat-lyrics-panel" && event.defaultPrevented)
          document.documentElement.dataset.blocked = Number(document.documentElement.dataset.blocked || 0) + 1
      })
    JS
    click_button "Ver prévia"
    assert_selector "dialog.ui-stage[open]"
    page.execute_script("document.getElementById('chat-lyrics-panel').dataset.sentinel = 'old'")
    OrderChatBroadcaster.call(order)
    assert_selector "html[data-blocked='1']", visible: :all
    assert_selector "#chat-lyrics-panel[data-sentinel=old] dialog.ui-stage[open]"
    assert_no_studio_errors
  end

  private

  def assert_mobile_phase(primary, changes)
    assert_equal 375, page.evaluate_script("window.innerWidth")
    assert_fits_horizontally
    within(".ui-actionbar") { assert_button primary, disabled: :all }
    bar = page.evaluate_script(<<~JS, primary)
      ((label) => {
        const bar = document.querySelector(".ui-actionbar")
        const button = Array.from(bar.querySelectorAll("button")).find(b => b.textContent.trim().startsWith(label))
        const box = button.getBoundingClientRect()
        const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2)
        return { position: getComputedStyle(bar).position, bottom: bar.getBoundingClientRect().bottom, height: innerHeight,
                 uncovered: button.contains(hit) || hit === button }
      })(arguments[0])
    JS
    assert_equal "fixed", bar["position"], "a barra de ação da fase precisa ser fixa no celular"
    assert_in_delta bar["height"], bar["bottom"], 1, "a barra de ação precisa ficar colada no fim da tela"
    assert bar["uncovered"], "nada pode cobrir o botão principal da barra"

    find("#{changes} > summary").click
    assert_selector "#{changes}[open]"
    last = page.evaluate_script(<<~JS, changes)
      ((selector) => {
        const box = document.querySelector(selector)
        box.querySelectorAll("details").forEach(details => { details.open = true })
        const fields = Array.from(box.querySelectorAll("textarea, button, input:not([type=hidden]), label"))
          .filter(field => field.getClientRects().length && field.getBoundingClientRect().height > 0)
        const field = fields[fields.length - 1]
        field.scrollIntoView({ block: "end" })
        return { field: field.outerHTML.slice(0, 120), bottom: field.getBoundingClientRect().bottom,
                 barTop: document.querySelector(".ui-actionbar").getBoundingClientRect().top }
      })(arguments[0])
    JS
    assert_operator last["bottom"], :<=, last["barTop"], "o último campo de #{changes} ficou atrás da barra: #{last.inspect}"
    assert_fits_horizontally
  end

  def assert_fits_horizontally
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "A página rola na horizontal"
  end

  def assert_no_studio_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action/) }
    assert_empty errors, errors.map(&:message).join("\n")
  end

  def prepare_sample(asset)
    asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4", metadata: { duration_seconds: 30 })
    asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
    asset.update!(campaign_preview_status: "ready")
  end
end
