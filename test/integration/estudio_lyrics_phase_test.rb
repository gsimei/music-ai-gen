require "test_helper"

# Fase 1 do estúdio (tarefa 5 do plano "caminho B"): "Revise a letra.", um só botão principal que
# aprova e gasta a primeira rodada, e "Quero mudar algo" com a reescrita por IA e os tiles do som.
class EstudioLyricsPhaseTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
    @order = orders(:b2b_lyrics_ready)
    @campaign = Campaign.create!(order: @order, business_name: "Café do Bairro", offer: "Café por R$ 12", contact: "@cafe",
      call_to_action: "Peça agora", style: "animado")
    @campaign.sync_briefing!
    @headers = { "ACCEPT" => "text/vnd.turbo-stream.html" }
  end

  test "lyrics_ready shows the review heading, one primary approve button and the round it spends" do
    get order_chat_path(order_id: @order.id)
    assert_response :success
    limit = Campaigns::MusicRounds::LIMIT
    assert_select '#chat-lyrics-panel[data-phase="1"]'
    assert_select "h1", count: 1
    assert_select "#chat-lyrics-panel h1[tabindex='-1']", text: "Revise a letra."
    assert_select ".ui-eyebrow", text: "Fase #{Campaigns::StudioPhase.step(:lyrics)} de 3"
    assert_select "#chat-lyrics-panel form[action=?]", order_chat_creation_path(order_id: @order.id) do
      assert_select "textarea#editable-lyrics[name=content]", text: @order.current_draft.content
      assert_select 'button[name=intent][value=save]', text: "Salvar letra"
      assert_select ".ui-btn-primary", count: 1
      assert_select '.ui-btn-primary[name=intent][value=generate]', text: /Aprovar letra e ouvir 2 versões/
    end
    described = css_select(".ui-btn-primary").first["aria-describedby"]
    assert described.present?, "o botão que gasta rodada precisa de aria-describedby"
    assert_select "##{described}", text: "Isso usa a rodada 1 de #{limit}."
  end

  test "Quero mudar algo is closed and holds the AI rewrite and the sound tiles, without native selects" do
    get order_chat_path(order_id: @order.id)
    assert_select "details#lyrics-changes:not([open])" do
      assert_select "summary", text: /Quero mudar algo/
      assert_select "details#rewrite-lyrics" do
        assert_select "textarea[name=lyrics_feedback]"
        assert_select "button[name=intent][value=rewrite]", text: "Reescrever com IA · #{@order.lyrics_regen_remaining} ajustes"
      end
      assert_select "details#creation-sound[data-controller~=genre-preview][data-genre-preview-catalog-value]" do
        assert_select 'input[type=radio][name="campaign[musical_genre]"]', count: Campaign::GENRES.size
        assert_select 'input[type=radio][name="campaign[vocal_gender]"]'
        assert_select 'input[type=radio][name="campaign[style]"]'
        assert_select ".ui-player audio[data-action*=?]", "play->creative-editor#play"
      end
    end
    assert_select "#chat-lyrics-panel select", count: 0
    assert_select "#chat-lyrics-panel audio[controls]", count: 0
  end

  test "the rewrite button pluralizes the adjustments left (M2)" do
    @order.update_column(:lyrics_regen_used, @order.lyrics_regen_limit - 1)
    get order_chat_path(order_id: @order.id)
    assert_select "button[name=intent][value=rewrite]", text: "Reescrever com IA · 1 ajuste"
  end

  test "the lyrics form keeps the creative-editor dirty guard wiring" do
    get order_chat_path(order_id: @order.id)
    form = css_select("#chat-lyrics-panel form[action='#{order_chat_creation_path(order_id: @order.id)}']").first
    assert_includes form["data-action"], "input->creative-editor#feedbackChanged"
    assert_includes form["data-action"], "turbo:submit-end->creative-editor#restoreChanges"
  end

  test "an exhausted rewrite budget offers no AI rewrite" do
    @order.update!(lyrics_regen_used: @order.lyrics_regen_limit)
    get order_chat_path(order_id: @order.id)
    assert_select "#rewrite-lyrics", count: 0
    assert_select "button[name=intent][value=rewrite]", count: 0
    assert_select "textarea[name=lyrics_feedback]", count: 0
    assert_select ".ui-btn-primary", text: /Aprovar letra/
  end

  test "lyrics_failed offers to prepare the lyrics again and nothing that spends a round" do
    @order.update!(status: "lyrics_failed")
    get order_chat_path(order_id: @order.id)
    assert_select '#chat-lyrics-panel[data-phase="1"]'
    assert_select "form[action=?] button", retry_generation_campaign_path(@campaign), text: "Tentar preparar a letra novamente"
    assert_select "button[value=generate]", count: 0
  end

  test "while the lyrics are being written the phase shows the wait card and no form" do
    @order.update!(status: "lyrics_drafting")
    get order_chat_path(order_id: @order.id)
    assert_select ".ui-wait .ui-wait-title", text: /Preparando sua letra/
    assert_select "textarea#editable-lyrics", count: 0
  end

  test "approving posts the edited text with intent=generate, saving the new draft and approving it" do
    get order_chat_path(order_id: @order.id)
    assert_enqueued_with(job: GenerateMusicJob, args: [ @order.id ]) do
      post order_chat_creation_path(order_id: @order.id), params: { intent: "generate", draft_id: @order.current_draft.id,
        content: "Café do Bairro, bom dia com café!", campaign: { musical_genre: "forro", vocal_gender: "female", style: "animado" } }, headers: @headers
    end
    assert_response :success
    assert @order.reload.lyrics_approved?
    assert_equal "Café do Bairro, bom dia com café!", @order.approved_lyrics_draft.content
    assert_equal "forro", @campaign.reload.musical_genre
  end
end
