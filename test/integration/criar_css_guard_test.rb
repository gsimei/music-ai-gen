require "test_helper"

# Guarda da base de CSS do Criar (tarefa 1 do plano "caminho B"). ui.css é a folha
# nova e isolada: sem cor escrita à mão, sem !important e sempre escopada em `.criar`
# ou `.ui-`, para nunca vazar para o estúdio, que ainda usa os CSS legados.
class CriarCssGuardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  UI_CSS = Rails.root.join("app/assets/stylesheets/ui.css")
  JINGLEPRO_CSS = Rails.root.join("app/assets/stylesheets/jinglepro.css")
  AT_RULE_OR_KEYFRAME_STEP = /\A(@|(from|to|\d+(\.\d+)?%)(\s*,\s*(from|to|\d+(\.\d+)?%))*\z)/

  setup do
    host! "b2b.lvh.me"
    sign_in users(:customer_b2b)
  end

  test "the ui stylesheet is linked after jinglepro on the Criar page" do
    get new_campaign_path
    assert_response :success
    hrefs = css_select('link[rel="stylesheet"]').map { |link| link["href"].to_s }
    jinglepro = hrefs.index { |href| href.match?(%r{/assets/jinglepro[-.]}) }
    ui = hrefs.index { |href| href.match?(%r{/assets/ui[-.]}) }
    assert jinglepro, "jinglepro.css deve estar no layout. Links: #{hrefs.inspect}"
    assert ui, "ui.css deve ser acrescentado ao stylesheet_link_tag do layout, depois de jinglepro. Links: #{hrefs.inspect}"
    assert_operator ui, :>, jinglepro, "ui.css precisa carregar depois de jinglepro.css para vencer sem !important"
  end

  test "ui.css has no hand-written colors" do
    css = declarations_only(ui_css)
    hex = css.scan(/:[^;{}]*?(#\h{3,8})(?![\w-])/).flatten
    assert_empty hex, "Cores em hexadecimal escritas à mão em ui.css: #{hex.inspect}. Use var(--jp-*)."
    functional = css.scan(/\b(?:rgba?|hsla?)\(/i)
    assert_empty functional, "Cores rgb()/rgba()/hsl()/hsla() escritas à mão em ui.css. Use var(--jp-*)."
  end

  test "ui.css never uses !important" do
    important = strip_comments(ui_css).scan(/!\s*important/i)
    assert_empty important, "ui.css vence por especificidade (.criar), não por !important"
  end

  test "every ui.css selector is scoped by .criar or a ui- class" do
    css = strip_comments(ui_css)
    preludes = css.scan(/([^{};]+)\{/).flatten.map(&:strip).reject { |prelude| prelude.match?(AT_RULE_OR_KEYFRAME_STEP) }
    assert_not_empty preludes, "ui.css não tem nenhuma regra ainda"
    unscoped = preludes.flat_map { |prelude| prelude.split(/,(?![^(]*\))/).map(&:strip) }
      .reject { |selector| selector.include?(".criar") || selector.include?(".ui-") }
    assert_empty unscoped, "Seletores fora de .criar/.ui- podem vazar para o estúdio: #{unscoped.inspect}"
  end

  test "ui.css no longer carries the provisional bridge for the legacy offer class" do
    assert_no_match(/campaign-offer-text/, strip_comments(ui_css),
      "A prévia nova (tarefa 5) estiliza previewOffer com classe ui-; a ponte .campaign-offer-text sai de ui.css")
    assert_no_match(/campaign-poster/, strip_comments(ui_css))
  end

  test "jinglepro.css defines the two on-forest tokens in :root" do
    assert File.exist?(JINGLEPRO_CSS), "jinglepro.css não encontrado"
    root = File.read(JINGLEPRO_CSS)[/:root\s*\{([^}]*)\}/m, 1].to_s
    assert_not_empty root, "jinglepro.css não tem bloco :root"
    muted = root[/--jp-on-forest-muted\s*:\s*(#\h{3,8})/, 1]
    line = root[/--jp-on-forest-line\s*:\s*(#\h{3,8})/, 1]
    assert muted, "--jp-on-forest-muted ausente do :root de jinglepro.css"
    assert line, "--jp-on-forest-line ausente do :root de jinglepro.css"
    assert muted.casecmp?("#B5C9BC"), "--jp-on-forest-muted deveria ser #B5C9BC, é #{muted}"
    assert line.casecmp?("#3F6253"), "--jp-on-forest-line deveria ser #3F6253, é #{line}"
  end

  # ---------- tarefas 6 e 7: classes legadas, literais e CSS morto ----------

  VIEW_ROOT = Rails.root.join("app/views/campaigns")
  FORBIDDEN_LITERALS = [ "3 rodadas", "20 reescritas", "R$ 29", "5 fotos", "12 segundos" ].freeze

  test "no element inside .criar carries a class starting with campaign- in any state of the page" do
    order = orders(:b2b_pending)
    campaign = Campaign.create!(business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90", contact: "@pizzariadavila",
      call_to_action: "Peça pelo WhatsApp", style: "animado", order: order)
    seen = {}
    record = lambda do |state|
      classes = css_select(".criar [class]").flat_map { |node| node["class"].to_s.split }
      assert_not_empty classes, "#{state}: .criar sem nenhuma classe, a página não renderizou o Criar"
      seen[state] = classes.grep(/\Acampaign-/).uniq
    end

    get new_campaign_path
    record.call("campanha nova")
    get campaign_path(campaign)
    record.call("campanha salva")
    order.update!(status: "payment_failed")
    get campaign_path(campaign)
    record.call("pagamento não concluído")
    order.update!(status: "pending", stripe_session_id: "cs_guard_started")
    open_session = Stripe::Checkout::Session.construct_from(id: "cs_guard_started", status: "open", payment_status: "unpaid", url: "https://checkout.stripe.com/guard")
    Stripe::Checkout::Session.stub(:retrieve, open_session) { get campaign_path(campaign) }
    record.call("checkout iniciado")
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    post campaigns_path, params: { campaign: { business_name: "x", offer: "", contact: "@x", call_to_action: "Peça pelo WhatsApp", style: "animado" } }
    assert_response :unprocessable_entity
    record.call("erro de validação")

    legacy = seen.reject { |_state, classes| classes.empty? }
    assert_empty legacy, "classes campaign-* dentro de .criar (ids como campaign-photo-help são permitidos): #{legacy.inspect}"
  end

  test "the Criar views never write a campaign- class, not even in states the test environment cannot render" do
    files = view_files
    assert_operator files.size, :>=, 8, "esperava new.html.erb e os partials de campaigns/new/: #{files.map(&:to_s)}"
    offenders = files.filter_map do |file|
      hits = File.read(file).scan(/class(?:=|:\s*)["'][^"']*(?<![\w-])(campaign-[\w-]+)/).flatten
      "#{file.relative_path_from(Rails.root)}: #{hits.uniq.join(', ')}" if hits.any?
    end
    assert_empty offenders, "classes legadas escritas nas views do Criar (inclui o bloco só de development)"
  end

  test "the Criar views carry no literal price, round, rewrite, photo or duration numbers" do
    files = view_files
    assert_not_empty files
    offenders = files.flat_map do |file|
      text = File.read(file)
      FORBIDDEN_LITERALS.select { |literal| text.include?(literal) }.map { |literal| "#{file.relative_path_from(Rails.root)}: #{literal.inspect}" }
    end
    assert_empty offenders, "valores fixos nas views do Criar: use campaign_price, MusicRounds::LIMIT, lyrics_regen_limit, PhotoLimit e o catálogo"
  end

  test "jinglepro.css no longer carries the campaign-review rules of the old review step" do
    css = File.read(JINGLEPRO_CSS)
    assert_no_match(/campaign-review/, css, "a classe campaign-review não existe mais no Criar nem no controller; as regras morrem junto")
    assert_no_match(/campaign-review/, File.read(Rails.root.join("app/javascript/controllers/campaign_form_controller.js")))
  end

  test "ui.css styles the tile, segmented control, player, summary, price card and alert, and keeps field_with_errors from breaking layout" do
    css = strip_comments(ui_css)
    %w[ui-tile ui-seg ui-player ui-summary ui-price ui-alert].each do |component|
      assert_match(/\.#{component}\b/, css, ".#{component} sem regra em ui.css")
    end
    wrappers = css.scan(/([^{}]*field_with_errors[^{}]*)\{([^}]*)\}/m)
    assert_not_empty wrappers, ".criar .field_with_errors precisa de regra em ui.css (decisão D9)"
    assert wrappers.any? { |selector, body| selector.include?(".criar") && body.match?(/display:\s*contents/) }, ".criar .field_with_errors { display: contents }"
  end

  private

  def ui_css
    assert File.exist?(UI_CSS), "app/assets/stylesheets/ui.css ainda não existe (tarefa 1 do plano)"
    File.read(UI_CSS)
  end

  def view_files
    ([ VIEW_ROOT.join("new.html.erb") ] + Dir[VIEW_ROOT.join("new/**/*.erb")].map { |path| Pathname.new(path) }).select(&:file?)
  end

  def strip_comments(css)
    css.gsub(%r{/\*.*?\*/}m, "")
  end

  # Remove comentários e url(...) para não confundir `#id` de SVG com cor.
  def declarations_only(css)
    strip_comments(css).gsub(/url\([^)]*\)/i, "url()")
  end
end
