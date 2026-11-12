require "application_system_test_case"
require "warden/test/helpers"
require "tmpdir"

class CampaignVideoPersonalizationSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup { Warden.test_mode! }
  teardown { Warden.test_reset! }

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
    assert_text "Fotos do seu vídeo"
    find(".creative-video-photos summary").click unless find(".creative-video-photos summary").find(:xpath, "..").matches_css?("details[open]")
    assert_selector ".creative-video-photos details[open] .campaign-photo-choose"
    page.scroll_to(find(".creative-video-photos .campaign-photo-choose"), align: :center)
    attach_file "Adicionar fotos ao vídeo", Rails.root.join("public/icon.png"), make_visible: true
    within ".creative-video-photos" do
      assert_selector ".campaign-photo-list figure", count: 2
      find('button[aria-label="Mover foto 2 para antes"]').click
      find('button[aria-label="Remover foto 2"]').click
      assert_selector ".campaign-photo-list figure", count: 1
      click_button "Salvar fotos do vídeo"
    end
    assert_selector ".creative-video-photos summary", text: "Ajustar fotos · 1 de 5"
    assert_selector '.creative-video-photos input[name="video_revision"][value="1"]', visible: :all
    assert_equal "icon.png", campaign.reload.product_photos.first.filename.to_s
    assert_equal 1, campaign.video_revision

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
    within ".creative-video-setup" do
      find("summary", text: "Personalizar duração e trecho").click unless find("summary", text: "Personalizar duração e trecho").find(:xpath, "..").matches_css?("details[open]")
      select "Personalizar duração", from: "Duração do vídeo"
      fill_in "Duração personalizada em segundos", with: "75.5"
      fill_in "Segundo inicial", with: "40"
      select "1 minuto e meio", from: "Duração do vídeo"
      assert_field "Segundo inicial", with: "30.25"
      assert_text "Vídeo de 1:30.0"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      take_screenshot
      click_button "Gerar meu vídeo"
    end
    assert_text "Salve ou envie a alteração"
    within ".creative-video-setup" do
      click_button "Preparar e ouvir este trecho"
      assert_text "Preparando o trecho do vídeo"
    end
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    within ".creative-video-setup" do
      assert_text "Trecho do vídeo de 1:30"
      find("summary", text: "Personalizar duração e trecho").click unless find("summary", text: "Personalizar duração e trecho").find(:xpath, "..").matches_css?("details[open]")
      select "Música inteira (2:00)", from: "Duração do vídeo"
      assert_field "Segundo inicial", with: "0"
      assert find_field("Segundo inicial").readonly?
      assert_text "Vídeo de 2:00.3"
      click_button "Preparar e ouvir este trecho"
      assert_text "Preparando o trecho do vídeo"
    end
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    within ".creative-video-setup" do
      assert_text "Trecho do vídeo de 2:00"
      assert_button "Gerar meu vídeo"
    end
    assert_selector ".creative-video-photos summary", text: "Ajustar fotos · 1 de 20"
    find(".creative-video-photos summary").click unless find(".creative-video-photos summary").find(:xpath, "..").matches_css?("details[open]")
    page.scroll_to(find(".creative-video-photos .campaign-photo-choose"), align: :center)
    Dir.mktmpdir do |dir|
      paths = Array.new(19) do |index|
        path = File.join(dir, "photo-#{index}.png")
        FileUtils.cp(Rails.root.join("public/icon.png"), path)
        path
      end
      attach_file "Adicionar fotos ao vídeo", paths, make_visible: true
      within ".creative-video-photos" do
        assert_selector ".campaign-photo-list figure", count: 20
        assert_text "20 de 20 fotos"
        find('button[aria-label="Mover foto 20 para antes"]').click
      end
      attach_file "Adicionar fotos ao vídeo", Rails.root.join("public/icon.png"), make_visible: true
      within ".creative-video-photos" do
        assert_text "Esta duração permite até 20 fotos"
        assert_selector ".campaign-photo-list figure", count: 20
        click_button "Salvar fotos do vídeo"
      end
      assert_selector '.creative-video-photos input[name="video_revision"][value="2"]', visible: :all
    end
    assert_equal 20, campaign.reload.product_photos.size
    assert_equal "photo-18.png", campaign.product_photos[-2].filename.to_s
    within ".creative-video-setup" do
      find("summary", text: "Personalizar duração e trecho").click unless find("summary", text: "Personalizar duração e trecho").find(:xpath, "..").matches_css?("details[open]")
      select "30 segundos", from: "Duração do vídeo"
      assert_text "Esta duração permite até 5 fotos"
      click_button "Preparar e ouvir este trecho"
      assert_text "Preparando o trecho do vídeo"
    end
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    within ".creative-video-setup" do
      assert_text "Você salvou 20 fotos"
      assert_button "Gerar meu vídeo", disabled: true
      find("summary", text: "Personalizar duração e trecho").click unless find("summary", text: "Personalizar duração e trecho").find(:xpath, "..").matches_css?("details[open]")
      select "Música inteira (2:00)", from: "Duração do vídeo"
      click_button "Preparar e ouvir este trecho"
      assert_text "Preparando o trecho do vídeo"
    end
    perform_enqueued_jobs(only: PrepareCampaignAudioJob)
    assert_selector ".creative-video-photos summary", text: "Ajustar fotos · 20 de 20"
    assert_equal 390, page.evaluate_script("window.innerWidth")
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    assert_nil asset.reload.excerpt_duration_seconds
    assert_in_delta 120.25, asset.campaign_audio.blob.metadata.fetch("duration_seconds"), 0.001
    within ".creative-video-setup" do
      click_button "Gerar meu vídeo"
    end
    assert_current_path campaign_path(campaign)
    assert order.reload.approved?
    assert_equal 1, order.completed_music_rounds
    assert_equal 0, order.generation_costs.where(operation: "music").count
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action/) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
