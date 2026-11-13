require "application_system_test_case"
require "warden/test/helpers"

class CampaignGuidedStudioSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "merchant edits lyrics and sound together and moves to video without losing earlier choices" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café fresquinho por R$ 12", show_cta: false)
    campaign.sync_briefing!
    draft = order.current_draft
    draft.update!(content: "Café do Bairro, venha experimentar!\nCafé fresquinho por doze reais.")
    order.all_music_assets.each { |asset| prepare_sample(asset) }
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Escolha a sua versão."
    assert_no_text "Fotos do seu vídeo"
    assert_no_text "Salvar favorita"
    page.save_screenshot(Rails.root.join("tmp/guided-studio-desktop.png"))
    chevron = "getComputedStyle(document.querySelector('#music-changes > summary'), '::after').transform"
    closed = page.evaluate_script(chevron)
    click_link "← Voltar à letra"
    assert_selector "#music-changes[open]"
    assert_selector "#estudio-change[open]"
    refute_equal closed, page.evaluate_script(chevron), "o chevron de \"Quero mudar algo\" precisa girar ao abrir (R8)"
    fill_in "editable-lyrics", with: "Café do Bairro, o seu dia começa aqui!"
    find("#creation-sound summary").click
    find("#creation-sound label.ui-tile", text: "Forró").click
    click_button "Mais animada"
    assert_field "Conte o que você quer diferente", with: "Mais animada"
    click_button "Usar a Versão A e montar o vídeo"
    assert_text "Salve ou envie a alteração"
    assert_field "editable-lyrics", with: "Café do Bairro, o seu dia começa aqui!"
    click_button "Salvar letra"
    assert_text "Alterações salvas."
    assert_selector "#music-changes[open]"
    assert_field "editable-lyrics", with: "Café do Bairro, o seu dia começa aqui!"
    assert_field "Conte o que você quer diferente", with: "Mais animada"
    assert_equal "forro", campaign.reload.musical_genre
    assert_equal 1, order.completed_music_rounds
    assert_includes draft.reload.content, "venha experimentar"

    assert_text "Isso usa a rodada 2 de #{Campaigns::MusicRounds::LIMIT}."
    click_button "Criar mais duas versões"
    assert_text "Criando duas novas versões"
    assert_current_path order_chat_path(order_id: order.id)
    generation = order.music_generations.order(:iteration).last
    assert_equal "Café do Bairro, o seu dia começa aqui!", generation.request_payload["lyrics"]
    assert_equal "Mais animada", generation.melody_hint
    generation.update!(status: "completed")
    2.times do |index|
      asset = order.order_assets.create!(music_generation: generation, kind: "music_variant", variant_index: index)
      prepare_sample(asset)
    end
    order.reload.music_ready!
    assert_selector ".ui-version", count: 2
    assert_selector "details#music-round-1 summary", text: "Rodada 1"
    assert_selector "#music-changes:not([open])"

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    page.scroll_to(:top)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot(Rails.root.join("tmp/guided-studio-mobile.png"))
    within "#music-version-#{generation.order_assets.order(:variant_index).last.id}" do
      find("label.ui-chip", text: "Escolher").click
    end
    click_button "Usar a Versão B e montar o vídeo"
    assert_selector "h1", text: "Monte o seu vídeo."
    assert_equal generation.order_assets.order(:variant_index).last.id, campaign.reload.selected_music_asset_id
    assert_button "Gerar meu vídeo"
    assert_no_selector "#editable-lyrics"
    assert order.reload.preview_ready?
    assert_equal "pending", campaign.reload.video_status
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot(Rails.root.join("tmp/guided-video-mobile.png"))
    click_button "← Voltar às músicas"
    assert_selector "h1", text: "Escolha a sua versão."
    click_link "← Voltar à letra"
    assert_field "editable-lyrics", with: "Café do Bairro, o seu dia começa aqui!"
    assert_equal 2, order.completed_music_rounds
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action/) }
    assert_empty errors, errors.map(&:message).join("\n")
  end

  test "first creation keeps rewritten lyrics visible before approving the lyrics" do
    order = orders(:b2b_lyrics_ready)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false)
    campaign.sync_briefing!
    order.current_draft.update!(content: "Café do Bairro, venha experimentar!")
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Revise a letra."
    assert_field "editable-lyrics", with: "Café do Bairro, venha experimentar!"
    assert_button "Aprovar letra e ouvir 2 versões"
    assert_text "Isso usa a rodada 1 de #{Campaigns::MusicRounds::LIMIT}."
    page.save_screenshot(Rails.root.join("tmp/guided-lyrics-desktop.png"))
    fill_in "editable-lyrics", with: "Café do Bairro, café por doze reais!"
    find("#lyrics-changes summary").click
    find("#rewrite-lyrics summary").click
    fill_in "O que você quer mudar na letra?", with: "Inclua bom dia"
    click_button "Reescrever com IA · #{order.lyrics_regen_remaining} ajustes"
    assert_text "Reescrevendo sua letra"
    assert_no_button "Aprovar letra e ouvir 2 versões"
    token = order.reload.lyrics_revision_token
    stub_request(:post, LyricsGenerator::MurekaLyricsClient::MUREKA_LYRICS_URL)
      .to_return(status: 200, body: { title: "Café", lyrics: "Bom dia! Café do Bairro, café por doze reais!" }.to_json)
    RewriteCampaignLyricsJob.perform_now(order.id, token, order.current_draft.id, "Inclua bom dia")
    assert_field "editable-lyrics", with: "Bom dia! Café do Bairro, café por doze reais!"
    assert_equal 0, order.completed_music_rounds
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 375, height: 812, deviceScaleFactor: 1, mobile: true)
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.save_screenshot(Rails.root.join("tmp/guided-lyrics-mobile.png"))
    click_button "Aprovar letra e ouvir 2 versões"
    assert_text "Criando duas versões"
    assert_current_path order_chat_path(order_id: order.id)
    assert order.reload.lyrics_approved?
    assert_equal "Bom dia! Café do Bairro, café por doze reais!", order.approved_lyrics_draft.content
  end

  test "a broadcast while the merchant types the lyrics keeps the typed text (RF 1)" do
    order = orders(:b2b_lyrics_ready)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false)
    campaign.sync_briefing!
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Revise a letra."
    # Controle: com o campo limpo, o broadcast chega e troca o painel.
    order.update!(lyrics_regen_used: 1)
    OrderChatBroadcaster.call(order)
    assert_selector ".ui-counters", text: /Ajustes de letra com IA: #{order.lyrics_regen_remaining}/
    fill_in "editable-lyrics", with: "Texto que o lojista está digitando"
    order.update!(lyrics_regen_used: 2)
    OrderChatBroadcaster.call(order)
    assert_no_selector ".ui-counters", text: /Ajustes de letra com IA: #{order.lyrics_regen_remaining}/, wait: 2
    assert_field "editable-lyrics", with: "Texto que o lojista está digitando"
  end

  private

  def prepare_sample(asset)
    asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4", metadata: { duration_seconds: 30 })
    asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
    asset.update!(campaign_preview_status: "ready")
  end
end
