require "test_helper"

# Casca do estúdio (tarefa 4 do plano "caminho B"): raiz `.estudio[data-phase]`, barra de 3 fases,
# contadores vindos do pedido e cartão de espera da rodada.
class EstudioShellTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
  end

  test "lyrics_ready marks Letra as the current phase" do
    order = studio_order(:b2b_lyrics_ready)
    get order_chat_path(order_id: order.id)
    assert_response :success
    assert_phase_bar current: "Letra", step: 1
    assert_select '#chat-lyrics-panel[data-controller="creative-editor"][data-creative-editor-view-value="lyrics"]'
  end

  test "preview_ready without a selection marks Músicas as the current phase" do
    order = studio_order(:b2b_preview_ready)
    get order_chat_path(order_id: order.id)
    assert_phase_bar current: "Músicas", step: 2
    assert_select '#chat-lyrics-panel[data-creative-editor-view-value="music"]'
  end

  test "preview_ready with a selection marks Vídeo as the current phase" do
    order = studio_order(:b2b_preview_ready)
    order.campaign.update!(selected_music_asset: order_assets(:music_variant_a))
    get order_chat_path(order_id: order.id)
    assert_phase_bar current: "Vídeo", step: 3
    assert_select '#chat-lyrics-panel[data-creative-editor-view-value="video"]'
  end

  test "counters come from the order, not from fixed numbers" do
    order = studio_order(:b2b_preview_ready)
    limit = Campaigns::MusicRounds::LIMIT
    get order_chat_path(order_id: order.id)
    assert_select ".ui-counters", text: /Rodadas: 1 de #{limit}/
    assert_select ".ui-counters", text: /Ajustes de letra com IA: #{order.lyrics_regen_remaining}/

    generation = music_generations(:generation_preview_ready)
    order.music_generations.create!(iteration: generation.iteration + 1, provider: "mureka", status: "completed",
      music_style: "pop", lyrics_draft: generation.lyrics_draft)
    order.update!(lyrics_regen_limit: 7, lyrics_regen_used: 3)
    get order_chat_path(order_id: order.id)
    assert_select ".ui-counters", text: /Rodadas: 2 de #{limit}/
    assert_select ".ui-counters", text: /Ajustes de letra com IA: 4/
  end

  test "lyrics_approved shows the round wait card" do
    order = studio_order(:b2b_lyrics_approved)
    get order_chat_path(order_id: order.id)
    assert_phase_bar current: "Músicas", step: 2
    assert_select ".ui-wait[role=status]" do
      assert_select ".ui-wait-title", text: /Criando duas versões/
      assert_select "*", text: /1 a 2 minutos/
    end
  end

  test "rate limited attempts become a line of the wait card" do
    order = studio_order(:b2b_lyrics_approved)
    order.music_generations.create!(iteration: 1, provider: "mureka", status: "failed", music_style: "pop",
      error_code: "rate_limited")
    get order_chat_path(order_id: order.id)
    assert_select ".ui-wait li", text: /serviço de música está ocupado/
  end

  test "the studio shell has no legacy studio-app wrapper" do
    order = studio_order(:b2b_preview_ready)
    get order_chat_path(order_id: order.id)
    assert_select ".studio-app", count: 0
    assert_select ".jp-workspace, .jp-workspace-grid", count: 0
    assert_select '.estudio[data-controller="creation-status"][data-creation-status-url-value][data-creation-status-version-value]'
    assert_select ".estudio #chat-lyrics-panel #creative-errors"
  end

  private

  def studio_order(name)
    order = orders(name)
    Campaign.create!(order: order, business_name: "Café do Bairro", offer: "Café por R$ 12", contact: "@cafe",
      call_to_action: "Peça agora", style: "animado")
    order
  end

  def assert_phase_bar(current:, step:)
    assert_select %(.estudio[data-phase="#{step}"])
    assert_select ".estudio nav.ui-phases li", count: 3
    assert_select ".estudio nav.ui-phases li", text: /Letra/
    assert_select ".estudio nav.ui-phases li", text: /Músicas/
    assert_select ".estudio nav.ui-phases li", text: /Vídeo/
    assert_select '.estudio nav.ui-phases li[aria-current="step"]', count: 1, text: /#{current}/
  end
end
