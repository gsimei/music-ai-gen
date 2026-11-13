require "test_helper"

# Fase 3 do estúdio (tarefa 7 do plano "caminho B"): "Monte o seu vídeo.", duração em primeira linha
# (chips que preparam o trecho), espaços de foto até o limite da duração, prévia 9:16 e "Quero mudar algo"
# com o início do trecho, a duração exata e a aparência do vídeo.
class EstudioVideoPhaseTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12",
      contact: "@cafe", call_to_action: "Peça agora", style: "animado")
    @asset = order_assets(:music_variant_a)
    @asset.update!(lyrics_sync: { "sections" => [ section("verse", 15_000, 28_000), section("chorus", 30_000, 45_000) ] })
    ready!(@asset)
    @campaign.update!(selected_music_asset: @asset)
  end

  test "the phase title is the only h1 and the legacy header is gone" do
    get order_chat_path(order_id: @order.id)
    assert_response :success
    assert_select '#chat-lyrics-panel[data-phase="3"]'
    assert_select "h1", count: 1
    assert_select "#chat-lyrics-panel h1[tabindex='-1']", text: "Monte o seu vídeo."
    assert_select ".ui-eyebrow", text: /Fase #{Campaigns::StudioPhase.step(:video)} de 3/
    assert_select ".creative-progress, .creative-video-setup", count: 0
    assert_select "form[action=?] button", order_chat_change_music_path(order_id: @order.id), text: "← Voltar às músicas"
    assert_select "#chat-lyrics-panel select", count: 0
    assert_select "#chat-lyrics-panel audio[controls]", count: 0
    assert_select ".ui-player[data-controller=ui-player] audio[src=?][data-action*=?]", @asset.campaign_playback_url, "play->creative-editor#play"
  end

  test "duration chips are submit buttons and 30 s is pressed by default" do
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-duration form[action=?]", order_chat_excerpt_settings_path(order_id: @order.id), count: 2
    assert_select ".ui-duration button[type=submit][name=duration_seconds]", count: 2
    assert_equal [ "30", "60", "full" ], css_select(".ui-duration button").map { |button| button["value"] }
    assert_select '.ui-duration button[value="30"][aria-pressed="true"]', text: /30 s.*ideal para Reels e Status/m
    assert_select '.ui-duration button[value="60"][aria-pressed="false"]', text: /até #{Campaigns::PhotoLimit.for_duration(60)} fotos/
    assert_select '.ui-duration button[value="full"]', text: /Música inteira 1:15/
    assert_select ".ui-duration form" do |forms|
      forms.each do |form|
        assert_select form, "input[type=hidden][name=asset_id][value=?]", @asset.id.to_s
        assert_select form, "input[type=hidden][name=preview_revision][value=?]", @asset.preview_revision.to_s
        assert_select form, "input[type=hidden][name=start_seconds]"
      end
    end
    assert_select ".ui-duration button[disabled]", count: 0
  end

  test "the pressed chip does not submit, so it never queues the same excerpt again" do
    @asset.update!(excerpt_start_seconds: nil)
    get order_chat_path(order_id: @order.id)
    assert_select '.ui-duration button[aria-pressed="true"]', count: 1 do |buttons|
      assert_equal "button", buttons.first["type"]
      assert_nil buttons.first["name"]
      assert_empty buttons.first.ancestors("form")
    end
  end

  test "a track shorter than the saved 30 s posts the whole song from the no-JS forms" do
    ready!(@asset, duration: 20, track: 20)
    @asset.update!(excerpt_duration_seconds: 30)
    get order_chat_path(order_id: @order.id)
    assert_equal [ "full" ], css_select(".ui-duration button").map { |button| button["value"] }
    assert_select '.ui-duration button[value="full"][aria-pressed="true"][type=button]'
    assert_select "#video-start input[type=hidden][name=duration_seconds][value=full]"
    assert_select "#video-exact input[type=hidden][name=duration_seconds][value=full]"
    assert_select "#video-exact input[type=hidden][name=start_seconds][value=?]", "0.0"
  end

  test "while the excerpt prepares every chip and Gerar meu vídeo are disabled (RF 2)" do
    @asset.update!(campaign_preview_status: "queued")
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-duration button", count: 3
    assert_select ".ui-duration button:not([disabled])", count: 0
    assert_select "form[action=?] button[disabled]", order_chat_approve_music_path(order_id: @order.id), text: "Gerar meu vídeo"
    assert_select "[role=status]", text: "Preparando o trecho…"
  end

  test "photo slots match the limit and announce the extra slots of a longer cut" do
    get order_chat_path(order_id: @order.id)
    assert_select "form[action=?] .ui-slot", order_chat_video_photos_path(order_id: @order.id), count: @campaign.reload.photo_limit
    assert_select ".ui-photos", text: /espaços liberados/, count: 0

    ready!(@asset, duration: 60)
    limit = @campaign.reload.photo_limit
    assert_operator limit, :>, Campaigns::PhotoLimit::INITIAL
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-photos .ui-slot", count: limit
    assert_select ".ui-photos", text: /\+#{limit - Campaigns::PhotoLimit::INITIAL} espaços liberados/
    assert_select '.ui-duration button[value="60"][aria-pressed="true"]'
  end

  test "one photo is singular" do
    attach_photos(1)
    get order_chat_path(order_id: @order.id)
    assert_match(/\b1 foto\b/, response.body)
    assert_no_match(/\b1 fotos\b/, response.body)
  end

  test "Mudar onde começa offers a keyboard range in m:ss and Ouvir a partir daqui with the full preview" do
    prepare_full(@asset)
    get order_chat_path(order_id: @order.id)
    assert_select "#video-changes > summary", text: "Quero mudar algo"
    assert_select "#video-start > summary", text: "Mudar onde começa"
    assert_select "#video-start form[action=?]", order_chat_excerpt_settings_path(order_id: @order.id) do
      assert_select "input[type=range][name=start_seconds]" do |ranges|
        assert_match(/\A\d+:\d{2}/, ranges.first["aria-valuetext"])
      end
      assert_select "input[type=hidden][name=duration_seconds][value=?]", "30.0"
      assert_select "button[name=automatic][value='1']", text: "Voltar ao trecho sugerido"
    end
    assert_select "#video-start button:not([hidden])", text: "Ouvir a partir daqui"
    assert_select "#video-start .ui-player audio[src=?][data-action*=?]", @asset.full_playback_url, "play->creative-editor#play"
  end

  test "without the full preview Ouvir a partir daqui is hidden" do
    get order_chat_path(order_id: @order.id)
    assert_select "#video-start button[hidden]", text: "Ouvir a partir daqui"
  end

  test "the timeline marks the lyrics sections as a percentage of the track" do
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-timeline-mark", count: 2
    assert_select ".ui-timeline-mark[style*=?]", "--at: 20.0%", text: /Verso/
    assert_select ".ui-timeline-mark[style*=?]", "--at: 40.0%", text: /Refrão/
  end

  test "without lyrics_sync there are no marks and nothing breaks" do
    @asset.update!(lyrics_sync: {})
    get order_chat_path(order_id: @order.id)
    assert_response :success
    assert_select ".ui-timeline-mark", count: 0
    assert_select "input[type=range][name=start_seconds]"
  end

  test "the exact duration is a mm:ss field" do
    get order_chat_path(order_id: @order.id)
    assert_select "#video-exact input[type=text][inputmode=numeric][pattern=?]", '\d{1,2}:\d{2}'
    assert_select "#video-exact input[type=hidden][name=duration_seconds]"
  end

  test "the 9:16 preview shows the first photo, the name, the offer and the strip" do
    attach_photos(2)
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-stage" do
      assert_select "img.ui-phone-photo[src*=?]", "rails/active_storage"
      assert_select ".ui-phone-name", text: "Café do Bairro"
      assert_select ".ui-phone-offer", text: @campaign.display_offer
      assert_select ".ui-phone-cta:not([hidden])", text: /@cafe/
    end
  end

  test "too many photos for the duration disables Gerar meu vídeo with a visible reason" do
    attach_photos(Campaigns::PhotoLimit::INITIAL + 1)
    get order_chat_path(order_id: @order.id)
    assert_select "form[action=?] button[disabled][aria-describedby~=video-finish-reason]", order_chat_approve_music_path(order_id: @order.id), text: "Gerar meu vídeo"
    assert_select "#video-finish-reason", text: /Você salvou #{Campaigns::PhotoLimit::INITIAL + 1} fotos/
  end

  test "Gerar meu vídeo posts the chosen version with the current revisions" do
    get order_chat_path(order_id: @order.id)
    assert_select "form[action=?]", order_chat_approve_music_path(order_id: @order.id) do
      assert_select "input[name=asset_id][value=?]", @asset.id.to_s
      assert_select "input[name=preview_revision][value=?]", @asset.preview_revision.to_s
      assert_select "input[name=video_revision][value=?]", @campaign.video_revision.to_s
      assert_select "button:not([disabled])", text: "Gerar meu vídeo"
    end
  end

  test "the appearance reuses the brand and contact fields as chips, without select" do
    get order_chat_path(order_id: @order.id)
    assert_select "#video-appearance form[action=?]", order_chat_video_appearance_path(order_id: @order.id) do
      assert_select "input[name=video_revision]"
      assert_select "input[name='campaign[business_name]']"
      assert_select "input[type=file][name='campaign[logo]']"
      assert_select "input[type=radio][name='campaign[call_to_action]']", minimum: Campaign::CTA_OPTIONS.size
      assert_select "input[type=color][name='campaign[cta_color]']"
      assert_select "select", count: 0
    end
  end

  private

  def section(type, start_at, end_at)
    { "section_type" => type, "lines" => [ { "start" => start_at, "end" => end_at } ] }
  end

  def ready!(asset, duration: 30, track: 75)
    asset.reload.campaign_audio.attach(io: StringIO.new("excerpt #{duration}"), filename: "excerpt.m4a", content_type: "audio/mp4",
      metadata: { preview_revision: asset.preview_revision, duration_seconds: duration, track_duration_seconds: track, start_seconds: 0 })
    asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: asset.preview_revision, watermark_version: Campaigns::AudioAudition::VERSION })
    asset.update!(campaign_preview_status: "ready", excerpt_duration_seconds: duration)
  end

  def prepare_full(asset)
    asset.audio.attach(io: StringIO.new("original"), filename: "original.mp3", content_type: "audio/mpeg")
    asset.full_audition_audio.attach(io: StringIO.new("marked full"), filename: "full.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.audio.blob.id, watermark_version: Campaigns::AudioAudition::VERSION })
  end

  def attach_photos(count)
    count.times do |index|
      @campaign.photos.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "foto-#{index}.png", content_type: "image/png")
    end
  end
end
