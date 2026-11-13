require "test_helper"

# Fase 2 do estúdio (tarefa 6 do plano "caminho B"): "Escolha a sua versão.", cartões A e B com o player
# da marca e a música completa com marca sonora, um só botão principal (rádios nos cartões) e
# "Quero mudar algo" com pedido rápido, som e letra para criar mais duas versões.
class EstudioMusicPhaseTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_preview_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12",
      contact: "@cafe", call_to_action: "Peça agora", style: "animado")
    @campaign.sync_briefing!
    @a = order_assets(:music_variant_a)
    @b = order_assets(:music_variant_b)
    [ @a, @b ].each { |asset| prepare_sample(asset) }
    @limit = Campaigns::MusicRounds::LIMIT
  end

  test "one round shows the phase title as the only h1 and two version cards with the brand player" do
    get order_chat_path(order_id: @order.id)
    assert_response :success
    assert_select '#chat-lyrics-panel[data-phase="2"]'
    assert_select "h1", count: 1
    assert_select "#chat-lyrics-panel h1[tabindex='-1']", text: "Escolha a sua versão."
    assert_select ".ui-eyebrow", text: /Fase #{Campaigns::StudioPhase.step(:music)} de 3/
    assert_select ".creative-progress", count: 0
    assert_select ".ui-lead", text: /Duas versões do mesmo trecho de 30 segundos/
    assert_select ".ui-version", count: 2
    [ [ @a, "Versão A" ], [ @b, "Versão B" ] ].each do |asset, name|
      assert_select "#music-version-#{asset.id}" do
        assert_select "h2", text: name
        assert_select ".ui-player[data-controller=ui-player] audio[src=?]", asset.campaign_playback_url
        assert_select ".ui-player audio[data-action*=?]", "play->creative-editor#play"
      end
    end
    assert_select "#chat-lyrics-panel audio[controls]", count: 0
    assert_select "#chat-lyrics-panel select", count: 0
  end

  test "a ready full preview offers Ouvir completa through the authenticated full route" do
    prepare_full(@a)
    get order_chat_path(order_id: @order.id)
    assert_select "#music-version-#{@a.id}" do
      assert_select ".ui-version-full", text: /Música completa 1:15/
      assert_select "a[href=?][data-action~=?]", order_audio_full_path(@order, asset_id: @a.id), "ui-player#listen", text: "Ouvir completa"
    end
    # B acabou de ficar pronta: a prévia completa ainda está sendo preparada, então só a duração.
    assert_select "#music-version-#{@b.id}" do
      assert_select ".ui-version-full", text: /Música completa 1:15/
      assert_select "a", text: "Ouvir completa", count: 0
      assert_select "form[action=?]", order_chat_prepare_audio_path(order_id: @order.id), count: 0
    end
  end

  test "an older version without the full preview offers to prepare it (P1)" do
    @b.audio.attach(io: StringIO.new("original"), filename: "original.mp3", content_type: "audio/mpeg")
    @b.audition_audio.blob.update!(created_at: 1.day.ago)
    get order_chat_path(order_id: @order.id)
    assert_select "#music-version-#{@b.id} form[action=?]", order_chat_prepare_audio_path(order_id: @order.id) do
      assert_select "input[name=asset_id][value=?]", @b.id.to_s
      assert_select "button", text: "Preparar música completa"
    end
  end

  test "one primary button; the card radios choose which asset the form sends" do
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-btn-primary", count: 1
    assert_select "form#music-pick[action=?]", order_chat_select_music_path(order_id: @order.id) do
      assert_select ".ui-btn-primary", text: /Usar a Versão A e montar o vídeo/
    end
    [ @a, @b ].each do |asset|
      assert_select "#music-version-#{asset.id} input[type=radio][name=asset_id][form=music-pick][value=?]", asset.id.to_s
    end
    assert_select "input[type=radio][name=asset_id][checked]", count: 1
    assert_select "input[type=radio][name=asset_id][value=?][checked]", @a.id.to_s
  end

  test "the favorite version starts checked" do
    @order.update!(favorite_music_asset: @b)
    get order_chat_path(order_id: @order.id)
    assert_select "input[type=radio][name=asset_id][value=?][checked]", @b.id.to_s
    assert_select ".ui-btn-primary", text: /Usar a Versão B e montar o vídeo/
    # M2: escolhida também em texto, não só pela cor.
    assert_select "#music-version-#{@b.id} label.ui-chip [data-pick-text]", text: "Escolhida"
    assert_select "#music-version-#{@a.id} label.ui-chip [data-pick-text]", text: "Escolher"
  end

  test "Quero mudar algo holds quick requests, feedback, sound and lyrics, and spends the next round" do
    get order_chat_path(order_id: @order.id)
    assert_select "details#music-changes:not([open])" do
      assert_select "summary", text: /Quero mudar algo/
      assert_select "form[action=?]", order_chat_creation_path(order_id: @order.id) do
        assert_select "button[type=button][data-action~=?][data-feedback]", "creative-editor#suggest", minimum: 4
        assert_select "textarea[name=feedback][maxlength='400'][data-creative-editor-target=feedback]"
        assert_select 'input[type=radio][name="campaign[musical_genre]"]', count: Campaign::GENRES.size
        assert_select "details#estudio-change textarea#editable-lyrics[name=content]"
        assert_select "input[name=draft_id][value=?]", @order.current_draft.id.to_s
        assert_select "button[name=intent][value=generate]", text: "Criar mais duas versões"
      end
    end
    note = css_select("button[name=intent][value=generate]").first["aria-describedby"]
    assert_select "##{note}", text: "Isso usa a rodada 2 de #{@limit}."
    assert_select "a[href='#estudio-change'][data-action~=?]", "creative-editor#reveal", text: "← Voltar à letra"
  end

  test "creating two more versions from the phase posts feedback and sound with intent=generate" do
    assert_enqueued_jobs 1, only: GenerateCampaignMusicJob do
      post order_chat_creation_path(order_id: @order.id), params: { intent: "generate", feedback: "Mais animada",
        draft_id: @order.current_draft.id, content: @order.current_draft.content,
        campaign: { musical_genre: "forro", vocal_gender: "female", style: "animado", music_notes: "" } },
        headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    assert @order.reload.music_generating?
    assert_equal "Mais animada", @order.music_generations.order(:iteration).last.melody_hint
    assert_equal "forro", @campaign.reload.musical_genre
  end

  test "no rounds left: nothing that spends a round, older rounds still selectable (RF 4)" do
    [ 2, 3 ].each do |iteration|
      @order.music_generations.create!(iteration: iteration, provider: "mureka", status: "completed",
        lyrics_draft: @order.current_draft, music_style: "pop")
    end
    assert_equal @limit, @order.completed_music_rounds
    get order_chat_path(order_id: @order.id)
    assert_select "button[name=intent][value=generate]", count: 0
    assert_select "button", text: "Criar mais duas versões", count: 0
    assert_select "#chat-lyrics-panel", text: /Você já usou as #{@limit} rodadas/
    assert_select "details summary", text: "Rodada 1"
    assert_select "details summary", text: "Rodada 2"
    assert_select "input[type=radio][name=asset_id][form=music-pick][value=?]", @a.id.to_s
    assert_select "details#music-round-1 input[name=asset_id][data-label=?]", "Usar a Versão A da rodada 1 e montar o vídeo"
    assert_select ".ui-btn-primary", count: 1
  end

  test "a phase-less order (StudioPhase nil) renders only the phase h1, not the legacy one" do
    @order.update_column(:status, "pending")
    assert_nil Campaigns::StudioPhase.for(@order)
    # pending nunca chega ao estúdio pela rota (redireciona); o partial é renderizado direto.
    html = ApplicationController.render(partial: "order_chat/campaign_studio", locals: { order: @order, draft: @order.current_draft })
    document = Nokogiri::HTML5.fragment(html)
    assert_equal 1, document.css("h1").size
    assert_empty document.css(".creative-progress")
  end

  test "music_failed shows the failure in the phase with a retry" do
    @order.update!(status: "music_failed")
    get order_chat_path(order_id: @order.id)
    assert_select '#chat-lyrics-panel[data-phase="2"]'
    assert_select ".ui-alert", text: /Esta tentativa não ficou pronta\./
    assert_select "form[action=?] button", retry_generation_campaign_path(@campaign), text: "Tentar novamente"
  end

  test "while the first round is created the phase shows the wait card and no pick form" do
    @order.music_generations.update_all(status: "processing")
    @order.update!(status: "music_generating")
    get order_chat_path(order_id: @order.id)
    assert_select "#chat-lyrics-panel h1", text: "Escolha a sua versão."
    assert_select ".ui-wait .ui-wait-title", text: "Criando duas versões…"
    assert_select "form#music-pick", count: 0
    assert_select "button[name=intent][value=generate]", count: 0
  end

  private

  def prepare_sample(asset)
    asset.campaign_audio.attach(io: StringIO.new("preview"), filename: "preview.m4a", content_type: "audio/mp4",
      metadata: { duration_seconds: 30, track_duration_seconds: 75 })
    asset.audition_audio.attach(io: StringIO.new("marked"), filename: "marked.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.campaign_audio.blob.id, preview_revision: 0, watermark_version: Campaigns::AudioAudition::VERSION })
    asset.update!(campaign_preview_status: "ready")
  end

  def prepare_full(asset)
    asset.audio.attach(io: StringIO.new("original"), filename: "original.mp3", content_type: "audio/mpeg")
    asset.full_audition_audio.attach(io: StringIO.new("marked full"), filename: "full.m4a", content_type: "audio/mp4",
      metadata: { source_blob_id: asset.audio.blob.id, watermark_version: Campaigns::AudioAudition::VERSION })
  end
end
