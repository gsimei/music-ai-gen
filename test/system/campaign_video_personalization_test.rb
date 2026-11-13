require "application_system_test_case"
require "warden/test/helpers"
require "tmpdir"

class CampaignVideoPersonalizationSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup { Warden.test_mode! }
  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    Warden.test_reset!
  end

  test "merchant edits photos and auditions a longer video before approving on mobile" do
    order = orders(:b2b_preview_ready)
    campaign = Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café com pão por R$ 12",
      contact: "@cafedobairro", call_to_action: "Venha tomar café", style: "animado")
    File.open(Rails.root.join("public/icon.png")) { |file| campaign.photos.attach(io: file, filename: "saved.png", content_type: "image/png") }
    asset = order_assets(:music_variant_a)
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.wav")
      Campaigns::MediaCommand.run!("ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=120.25", source)
      File.open(source) { |file| asset.audio.attach(io: file, filename: "source.wav", content_type: "audio/wav") }
    end
    PrepareCampaignAudioJob.perform_now(asset.id)
    campaign.update!(selected_music_asset: asset)
    login_as users(:customer_b2b), scope: :user
    visit order_chat_path(order_id: order.id)
    assert_selector "h1", text: "Monte o seu vídeo."
    assert_selector "#video-photos .ui-slot", count: Campaigns::PhotoLimit::INITIAL
    page.scroll_to(find("#video-photos"), align: :center)
    attach_file "Fotos do vídeo", Rails.root.join("public/icon.png"), make_visible: true
    within "#video-photos" do
      assert_selector "figure.ui-slot", count: 2
      assert_selector ".ui-slot", count: Campaigns::PhotoLimit::INITIAL
      find('button[aria-label="Mover foto 2 para antes"]').click
      find('button[aria-label="Remover foto 2"]').click
      assert_selector "figure.ui-slot", count: 1
      click_button "Salvar fotos do vídeo"
    end
    assert_selector '#video-photos input[name="video_revision"][value="1"]', visible: :all
    assert_text "1 foto salva"
    assert_equal "icon.png", campaign.reload.product_photos.first.filename.to_s
    assert_equal 1, campaign.video_revision

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    open_change("#video-exact")
    fill_in "Duração do vídeo (minutos:segundos)", with: "1:30"
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    take_screenshot
    click_button "Gerar meu vídeo"
    assert_text "Salve ou envie a alteração"
    within("#video-exact") { click_button "Preparar com esta duração" }
    assert_text "Preparando o trecho…"
    assert_selector ".ui-duration button[disabled]", count: 4
    assert_equal BigDecimal("90"), asset.reload.excerpt_duration_seconds
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    assert_selector '.ui-duration button[value="90"][aria-pressed="true"]'
    assert_selector ".ui-player", text: "Trecho do vídeo"

    click_button "Música inteira 2:00"
    assert_text "Preparando o trecho…"
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    assert_selector '.ui-duration button[value="full"][aria-pressed="true"]'
    assert_button "Gerar meu vídeo", disabled: false
    assert_selector "#video-photos .ui-slot", count: 20
    assert_selector "#video-photos .ui-badge", text: "+15 espaços liberados"
    page.scroll_to(find("#video-photos"), align: :center)
    Dir.mktmpdir do |dir|
      paths = Array.new(19) do |index|
        path = File.join(dir, "photo-#{index}.png")
        FileUtils.cp(Rails.root.join("public/icon.png"), path)
        path
      end
      attach_file "Fotos do vídeo", paths, make_visible: true
      within "#video-photos" do
        assert_selector "figure.ui-slot", count: 20
        assert_text "20 de 20 fotos"
        find('button[aria-label="Mover foto 20 para antes"]').click
      end
      attach_file "Fotos do vídeo", Rails.root.join("public/icon.png"), make_visible: true
      within "#video-photos" do
        assert_text "Esta duração permite até 20 fotos"
        assert_selector "figure.ui-slot", count: 20
        click_button "Salvar fotos do vídeo"
      end
      assert_selector '#video-photos input[name="video_revision"][value="2"]', visible: :all
    end
    assert_equal 20, campaign.reload.product_photos.size
    assert_equal "photo-18.png", campaign.product_photos[-2].filename.to_s

    click_button "30 s"
    assert_text "Preparando o trecho…"
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    assert_selector "#video-finish-reason", text: "Você salvou 20 fotos"
    assert_button "Gerar meu vídeo", disabled: true
    click_button "Música inteira 2:00"
    assert_text "Preparando o trecho…"
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    assert_selector "#video-photos figure.ui-slot", count: 20
    assert_equal 390, page.evaluate_script("window.innerWidth")
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert_nil asset.reload.excerpt_duration_seconds
    assert_in_delta 120.25, asset.campaign_audio.blob.metadata.fetch("duration_seconds"), 0.001
    click_button "Gerar meu vídeo"
    assert_current_path campaign_path(campaign)
    assert order.reload.approved?
    assert_equal 1, order.completed_music_rounds
    assert_equal 0, order.generation_costs.where(operation: "music").count
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action/) }
    assert_empty errors, errors.map(&:message).join("\n")
  end

  private

  def open_change(id)
    find("#video-changes > summary").click unless page.has_css?("#video-changes[open]", wait: 0)
    find("#{id} > summary").click unless page.has_css?("#{id}[open]", wait: 0)
  end
end
