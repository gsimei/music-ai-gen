require "test_helper"

# Tarefa 8 do plano "caminho B": montando, falha do vídeo e Entrega em `campaigns/show` com a casca do estúdio.
# A barra de fases e o h1 ficam dentro de #campaign-delivery, para o replace do polling/broadcast não deixá-los velhos.
class EstudioDeliveryTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12",
      contact: "@cafe", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @asset.campaign_audio.attach(io: StringIO.new("excerpt"), filename: "excerpt.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: @asset.preview_revision, duration_seconds: 45, track_duration_seconds: 75, start_seconds: 0 })
    @asset.update!(campaign_preview_status: "ready", excerpt_duration_seconds: 45)
  end

  test "before approval the page keeps the link back to the studio" do
    get campaign_path(@campaign)
    assert_response :success
    assert_select ".estudio"
    assert_select ".studio-app, .campaign-app", count: 0
    assert_select "h1", count: 1
    assert_select "a[href=?]", order_chat_path(order_id: @order.id), text: "Acompanhar e escolher a música"
  end

  test "queued video shows the phase bar on Vídeo and the checklist with the excerpt duration" do
    approve!(video_status: "queued")
    get campaign_path(@campaign)
    assert_response :success
    assert_select ".estudio"
    assert_select ".studio-app, .campaign-app", count: 0
    assert_select "turbo-cable-stream-source"
    assert_select "#campaign-delivery[data-controller=creation-status][data-creation-status-url-value=?][data-creation-status-version-value=queued]",
      status_campaign_path(@campaign)
    assert_select "#campaign-delivery nav.ui-phases li", count: 3
    assert_select '#campaign-delivery nav.ui-phases li[aria-current="step"]', text: /Vídeo/
    assert_select "h1", count: 1
    assert_select "#campaign-delivery h1", text: "Montando o seu vídeo."
    assert_select ".ui-eyebrow", text: "Fase #{Campaigns::StudioPhase.step(:rendering)} de 3"
    assert_select ".ui-checklist li.is-done", text: /Música escolhida · trecho de 0:45\z/
    assert_select ".ui-checklist li", text: /Montando o vídeo com as fotos e a oferta/
    assert_select ".ui-checklist li", text: /Pronto para baixar e postar/
    assert_select "a[href=?]", songs_path, text: "Ir para minhas campanhas"
  end

  test "failed video keeps the music and offers to try again" do
    approve!(video_status: "failed", video_error: "O vídeo não ficou pronto.")
    get campaign_path(@campaign)
    assert_select "h1", count: 1
    assert_select "#campaign-delivery h1", text: "A música está salva."
    assert_select '#campaign-delivery .ui-alert[role="alert"]', text: /O vídeo não ficou pronto./
    assert_select "form[action=?] button", render_video_campaign_path(@campaign), text: "Tentar montar o vídeo novamente"
    assert_select '#campaign-delivery nav.ui-phases li[aria-current="step"]', text: /Vídeo/
  end

  test "ready video activates the fourth phase, Entrega, with downloads and caption" do
    approve!(video_status: "ready")
    @campaign.video.attach(io: StringIO.new("mp4"), filename: "campanha.mp4", content_type: "video/mp4", metadata: { duration_seconds: 45 })
    @asset.audio.attach(io: StringIO.new("mp3"), filename: "musica.mp3", content_type: "audio/mpeg")
    get campaign_path(@campaign)
    assert_select "#campaign-delivery nav.ui-phases li", count: 4
    assert_select '#campaign-delivery nav.ui-phases li[aria-current="step"]', text: /Entrega/
    assert_select "h1", count: 1
    assert_select "#campaign-delivery h1", text: "Sua campanha está pronta."
    assert_select "video[controls] source[src=?]", download_campaign_path(@campaign, preview: 1)
    assert_select "*", text: "Vídeo MP4 vertical (9:16) · 0:45"
    assert_select "a[href=?]", download_campaign_path(@campaign), text: "Baixar vídeo MP4"
    assert_select "a[href=?][download]", @asset.reload.playback_url, text: "Baixar música MP3"
    assert_select "[data-controller=campaign-form] textarea[readonly][data-campaign-form-target=caption]", text: @campaign.caption
    assert_select 'button[data-action="campaign-form#copy"]', text: "Copiar legenda"
    assert_select "audio[controls]", count: 0
  end

  test "the status stream carries the phase bar with the delivery" do
    approve!(video_status: "ready")
    @campaign.video.attach(io: StringIO.new("mp4"), filename: "campanha.mp4", content_type: "video/mp4")
    get status_campaign_path(@campaign), params: { version: "rendering" }
    assert_response :success
    assert_includes response.body, 'target="campaign-delivery"'
    assert_includes response.body, "ui-phases"
    assert_includes response.body, "Entrega"
  end

  test "the studio route shows the same delivery with a single h1" do
    approve!(video_status: "rendering")
    get order_chat_path(order_id: @order.id)
    assert_response :success
    assert_select "#chat-lyrics-panel #campaign-delivery"
    assert_select "nav.ui-phases", count: 1
    assert_select "h1", count: 1
    assert_select "#campaign-delivery h1", text: "Montando o seu vídeo."
    assert_select ".creative-progress", count: 0
  end

  private

  def approve!(**campaign_attributes)
    @order.update!(status: "approved", approved_variant: "a", approved_music_generation_id: @asset.music_generation_id)
    @campaign.update!(campaign_attributes)
  end
end
