require "application_system_test_case"
require "warden/test/helpers"

# Fase 3 do estúdio no navegador (tarefa 7): o chip de duração envia o form e o trecho entra em preparo; "Ouvir a partir
# daqui" posiciona a prévia completa no ponto escolhido mesmo antes do metadata carregar. Sem FFmpeg: o preparo fica
# enfileirado e os áudios são anexos de mentira.
class EstudioVideoPhaseSystemTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    Warden.test_mode!
    login_as users(:customer_b2b), scope: :user
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12", show_cta: false)
    @asset = order_assets(:music_variant_a)
    @asset.audio.attach(io: StringIO.new("original"), filename: "original.mp3", content_type: "audio/mpeg")
    @asset.campaign_audio.attach(io: StringIO.new("excerpt"), filename: "excerpt.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: 0, duration_seconds: 30, track_duration_seconds: 75, start_seconds: 0 })
    @asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: @asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
    @asset.update!(campaign_preview_status: "ready")
    @campaign.update!(selected_music_asset: @asset)
  end

  teardown { Warden.test_reset! }

  test "choosing 1 min submits the chip and shows the excerpt being prepared" do
    visit order_chat_path(order_id: @order.id)
    assert_selector '.ui-duration button[value="30"][aria-pressed="true"]'
    assert_enqueued_with(job: PrepareCampaignAudioJob) { click_button "1 min" ; assert_text "Preparando o trecho…" }
    assert_selector ".ui-duration button:not([disabled])", count: 0
    assert_button "Gerar meu vídeo", disabled: true
    assert_equal BigDecimal("60"), @asset.reload.excerpt_duration_seconds
    assert_equal "queued", @asset.campaign_preview_status
    assert_no_javascript_errors
  end

  test "Ouvir a partir daqui seeks the full preview to the chosen start" do
    @asset.full_audition_audio.attach(io: StringIO.new("marked full"), filename: "full.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: @asset.audio.blob.id, watermark_version: Campaigns::AudioAudition::VERSION })
    visit order_chat_path(order_id: @order.id)
    find("#video-changes > summary").click
    find("#video-start > summary").click
    range = find("#video-start-range")
    range.click
    range.send_keys(:home, :right, :right, :page_up)
    assert_equal "12", page.evaluate_script("document.getElementById('video-start-range').value")
    assert_equal "0:12,0 a 0:42,0", range["aria-valuetext"]
    assert_text "Trecho de 0:12,0 a 0:42,0"
    click_button "Ouvir a partir daqui"
    # Antes do metadata, currentTime devolve a posição inicial que o play vai usar.
    assert_in_delta 12, page.evaluate_script("document.querySelector('#video-start audio').currentTime"), 0.01
    assert_equal 0, page.evaluate_script("Array.from(document.querySelectorAll('audio')).filter(a => !a.closest('#video-start') && a.currentTime > 0).length")
  end

  private

  def assert_no_javascript_errors
    errors = page.driver.browser.logs.get(:browser).select { |entry| entry.level == "SEVERE" && entry.message.match?(/Uncaught|Error connecting controller|Error invoking action/) }
    assert_empty errors, errors.map(&:message).join("\n")
  end
end
