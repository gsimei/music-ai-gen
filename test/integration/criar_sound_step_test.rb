require "test_helper"

# Passo 2 do Criar, "Sua música" (tarefa 6 do plano "caminho B"): tiles de ritmo, voz segmentada,
# clima em chips, "+ Detalhes do som" e o cartão do player da marca. O <audio> nativo fica por baixo,
# sem controles e sem autoplay. Os exemplos são arquivos estáticos: nenhuma chamada à Mureka.
class CriarSoundStepTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  GENRE_RADIOS = 'input[type="radio"][name="campaign[musical_genre]"]'.freeze
  VOICE_RADIOS = 'input[type="radio"][name="campaign[vocal_gender]"]'.freeze
  STYLE_RADIOS = 'input[type="radio"][name="campaign[style]"]'.freeze
  PLAYER_TARGET = '[data-genre-preview-target="%s"]'.freeze
  HINT_AUTO = "Escolha um ritmo para ouvir um exemplo antes de decidir.".freeze

  setup do
    host! "b2b.lvh.me"
    stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError.new("Checkout unavailable"))
    sign_in users(:customer_b2b)
    @attributes = { business_name: "Pizzaria da Vila", offer: "Duas pizzas por R$ 79,90, nesta terça", contact: "@pizzariadavila",
      call_to_action: "Peça pelo WhatsApp", style: "animado" }
  end

  # ---------- título e estrutura do passo ----------

  test "the step opens with the question as an h2 with one italic word, inside the second step section" do
    get new_campaign_path
    assert_response :success
    assert_equal 3, step_sections.size
    heading = sound_section.at_css("h2")
    assert heading, "o passo 2 precisa de um h2"
    assert_equal "Como sua promoção deve soar?", heading.text.squish
    assert_equal [ "soar?" ], heading.css("em").map { |node| node.text.squish }
    assert_match(/cantada em português/i, sound_section.text)
  end

  test "every sound field lives inside the step 2 section so it is enabled and sent with that step" do
    get new_campaign_path
    selectors = [ GENRE_RADIOS, VOICE_RADIOS, STYLE_RADIOS, 'textarea[name="campaign[music_notes]"]' ]
    selectors.each do |selector|
      assert_equal css_select("form.ui-form #{selector}").size, sound_section.css(selector).size, "#{selector} fora da section do passo 2"
      assert_operator sound_section.css(selector).size, :>=, 1, selector
    end
  end

  test "the step uses no legacy campaign, jp or studio field classes" do
    get new_campaign_path
    classes = ([ sound_section ] + sound_section.css("[class]").to_a).flat_map { |node| node["class"].to_s.split }
    legacy = classes.grep(/\A(campaign-|jp-|studio-field|studio-button|studio-kicker|creative-)/)
    assert_not_empty classes, "o passo 2 precisa de classes ui-"
    assert_empty legacy, "classes legadas no passo 2: #{legacy.uniq.inspect}"
    assert_empty sound_section.css("details, select"), "o passo 2 não usa <details> nem <select>"
  end

  test "loading the step never triggers a generation or a cost" do
    assert_no_difference [ "MusicGeneration.count", "GenerationCost.count", "Order.count" ] do
      get new_campaign_path
    end
    assert_response :success
  end

  # ---------- ritmo: tiles ----------

  test "there is one required radio tile per genre in catalog order, with name and description apart" do
    get new_campaign_path
    radios = sound_section.css(GENRE_RADIOS)
    assert_equal Campaign::GENRES.keys, radios.map { |radio| radio["value"] }
    radios.each do |radio|
      assert radio.key?("required"), "#{radio['value']}: rádio de ritmo obrigatório"
      assert_equal "genre", radio["data-sound-setting"]
      assert_equal "genre", radio["data-genre-preview-target"]
      assert_includes radio["data-action"].to_s.split, "change->genre-preview#select"
      tile = radio.ancestors("label.ui-tile").first
      assert tile, "#{radio['value']}: o rádio precisa estar dentro de label.ui-tile"
      name, description = Campaign::GENRES.fetch(radio["value"]).fetch(:label).split(" · ", 2)
      assert_equal name, tile.at_css(".ui-tile-name")&.text&.squish, radio["value"]
      assert_equal name, radio["data-sound-label"], "#{radio['value']}: data-sound-label leva só o nome"
      if description
        assert_equal description, tile.at_css(".ui-tile-desc")&.text&.squish, radio["value"]
        assert_equal description, radio["data-genre-description"], radio["value"]
        assert_not_includes tile.text, " · ", "#{radio['value']}: o separador não aparece no tile"
      end
    end
    assert_match(/Qual ritmo combina com (o )?seu negócio\?/, sound_section.at_css("fieldset legend")&.text.to_s)
  end

  test "choose for me has a sparkle icon hidden from assistive tech and no description" do
    get new_campaign_path
    radio = sound_section.at_css(%(#{GENRE_RADIOS}[value="auto"]))
    tile = radio.ancestors("label.ui-tile").first
    assert tile, "o rádio 'auto' precisa estar dentro de label.ui-tile"
    assert_equal "Escolher por mim", tile.at_css(".ui-tile-name")&.text&.squish
    icon = tile.at_css('svg[aria-hidden="true"]')
    assert icon, "o tile 'Escolher por mim' leva um ícone de brilho com aria-hidden"
    assert_empty tile.css(".ui-tile-desc").select { |node| node.text.squish.present? }
    assert radio["data-genre-description"].to_s.empty?, "sem descrição para 'Escolher por mim'"
  end

  test "a new campaign checks pop and a loaded identity checks its own genre, voice and climate" do
    get new_campaign_path
    assert_equal [ "pop" ], checked_values(GENRE_RADIOS)
    assert_equal [ "auto" ], checked_values(VOICE_RADIOS)
    assert_equal [ "animado" ], checked_values(STYLE_RADIOS)

    profile = users(:customer_b2b).business_music_profiles.create!(business_name: "Pizzaria da Vila", musical_genre: "forro",
      vocal_gender: "female", style: "acolhedor", music_notes: "Sanfona em destaque")
    get new_campaign_path(music_profile_id: profile.id)
    assert_equal [ "forro" ], checked_values(GENRE_RADIOS)
    assert_equal [ "female" ], checked_values(VOICE_RADIOS)
    assert_equal [ "acolhedor" ], checked_values(STYLE_RADIOS)
  end

  # ---------- voz ----------

  test "the voice is a segmented control with the three vocal genders" do
    get new_campaign_path
    group = sound_section.at_css(".ui-seg")
    assert group, "a voz é um controle segmentado .ui-seg"
    assert_equal "Como você imagina a voz?", group.ancestors("fieldset").first.at_css("legend").text.squish
    radios = group.css(VOICE_RADIOS)
    assert_equal Campaign::VOCAL_GENDERS.keys, radios.map { |radio| radio["value"] }
    radios.each do |radio|
      assert radio.key?("required"), radio["value"]
      assert_equal "voice", radio["data-sound-setting"]
      assert_equal Campaign::VOCAL_GENDERS.fetch(radio["value"]), radio["data-sound-label"]
      assert_includes radio.ancestors("label").first.text.squish, Campaign::VOCAL_GENDERS.fetch(radio["value"])
    end
  end

  # ---------- clima ----------

  test "the climate is three chips with name and description, the selected one carrying its sound label" do
    get new_campaign_path
    radios = sound_section.css(STYLE_RADIOS)
    assert_equal Campaign::STYLES.keys, radios.map { |radio| radio["value"] }
    assert_equal "Qual é o clima?", radios.first.ancestors("fieldset").first.at_css("legend").text.squish
    radios.each do |radio|
      style = Campaign::STYLES.fetch(radio["value"])
      chip = radio.ancestors("label.ui-chip").first
      assert chip, "#{radio['value']}: o clima é um label.ui-chip"
      assert radio.key?("required"), radio["value"]
      assert_equal "climate", radio["data-sound-setting"]
      assert_equal style[:label], radio["data-sound-label"]
      assert_includes chip.text, style[:label]
      assert_includes chip.text, style[:description]
    end
  end

  # ---------- detalhes do som ----------

  test "details start closed behind a plus button that controls the notes field" do
    get new_campaign_path
    button = sound_section.css("button[type=button]").find { |node| node.text.squish == "+ Detalhes do som" }
    assert button, "botão '+ Detalhes do som' ausente"
    assert_equal "false", button["aria-expanded"]
    region = sound_section.at_css("##{button['aria-controls']}")
    assert region, "aria-controls precisa apontar para um elemento do passo"
    assert region.key?("hidden"), "a região dos detalhes começa fechada"
    notes = region.at_css('textarea#campaign_music_notes[name="campaign[music_notes]"]')
    assert notes, "o textarea de music_notes fica dentro da região controlada"
    assert_equal "240", notes["maxlength"]
    assert_equal "Detalhes do som", sound_section.at_css("label[for=campaign_music_notes]")&.text&.squish
  end

  test "details start open when the campaign already has notes" do
    profile = users(:customer_b2b).business_music_profiles.create!(business_name: "Pizzaria da Vila", musical_genre: "forro",
      vocal_gender: "female", style: "animado", music_notes: "Sanfona em destaque")
    get new_campaign_path(music_profile_id: profile.id)
    button = sound_section.css("button[type=button]").find { |node| node.text.squish.include?("Detalhes do som") }
    assert button, "botão '+ Detalhes do som' ausente"
    assert_equal "true", button["aria-expanded"]
    region = sound_section.at_css("##{button['aria-controls']}")
    assert_not region.key?("hidden")
    assert_equal "Sanfona em destaque", region.at_css("textarea#campaign_music_notes").text.strip
  end

  # ---------- player da marca ----------

  test "there is exactly one brand player card wrapping one silent audio element in the genre-preview scope" do
    get new_campaign_path
    assert_select ".ui-player", count: 1
    assert_select '[data-controller~="genre-preview"]', count: 1
    assert_select "audio", count: 1
    scope = css_select('[data-controller~="genre-preview"]').first
    player = scope.at_css(".ui-player")
    assert player, ".ui-player dentro do escopo genre-preview"
    assert scope.at_css(GENRE_RADIOS), "os tiles de ritmo ficam no mesmo escopo genre-preview do player"
    audio = player.at_css("audio")
    assert audio, "o <audio> fica dentro do cartão"
    assert_equal "none", audio["preload"]
    assert_equal "player", audio["data-genre-preview-target"]
    assert_not audio.key?("autoplay"), "nenhum som sem clique"
    assert_not audio.key?("controls"), "o player nativo cinza sai do Criar"
    assert_includes audio["data-action"].to_s, "play->genre-preview#play"
    assert_includes audio["data-action"].to_s, "error->genre-preview#error"
    assert_includes scope["data-action"].to_s, "visibilitychange@document->genre-preview#visibilityChanged"
  end

  test "the card exposes the optional targets the controller drives" do
    get new_campaign_path
    player = player_card
    %w[toggle current duration wave name description hint error].each do |target|
      assert_equal 1, player.css(format(PLAYER_TARGET, target)).size, "alvo genre-preview #{target} ausente do cartão"
    end
    toggle = card_target(player, "toggle")
    assert_equal "button", toggle.name
    assert_equal "button", toggle["type"]
    assert_equal "Tocar exemplo", toggle["aria-label"]
    assert_includes toggle["data-action"].to_s.split, "genre-preview#toggle"
    assert_operator card_target(player, "wave").element_children.size, :>=, 5, "onda de barras fixas"
  end

  test "the card names the saved genre and shows the real sample duration from the catalog" do
    get new_campaign_path
    player = player_card
    assert_equal "Pop", card_target(player, "name").text.squish
    assert_equal "alegre e versátil", card_target(player, "description").text.squish
    assert_equal "0:00", card_target(player, "current").text.squish
    expected = ApplicationController.helpers.campaign_media_time(Campaigns::GenreSamples.catalog.fetch("pop").fetch(:duration_seconds))
    assert_equal expected, card_target(player, "duration").text.squish
  end

  test "a stubbed catalog with a duration is shown as minutes and seconds" do
    profile = users(:customer_b2b).business_music_profiles.create!(business_name: "Pizzaria da Vila", musical_genre: "forro",
      vocal_gender: "female", style: "animado")
    catalog = { "forro" => { url: "/demos/genres/forro-v1.mp3", label: "Forró", duration_seconds: 12.0 } }
    Campaigns::GenreSamples.stub(:catalog, catalog) do
      get new_campaign_path(music_profile_id: profile.id)
    end
    assert_response :success
    player = player_card
    assert_equal "0:12", card_target(player, "duration").text.squish
    assert_equal "Forró", card_target(player, "name").text.squish
    assert_equal "sanfona e alegria", card_target(player, "description").text.squish
  end

  test "the catalog handed to the controller carries the duration and no sample is a view error" do
    get new_campaign_path
    catalog = JSON.parse(css_select('[data-controller~="genre-preview"]').first["data-genre-preview-catalog-value"])
    assert_equal Campaign::GENRES.keys - [ "auto" ], catalog.keys
    catalog.each do |key, sample|
      assert sample.key?("duration_seconds"), "#{key}: duration_seconds ausente do catálogo entregue ao controller"
      assert_in_delta 12, sample["duration_seconds"], 0.5, key
    end

    Campaigns::GenreSamples.stub(:catalog, {}) do
      get new_campaign_path
    end
    assert_response :success
    assert_select ".ui-player", count: 1
  end

  test "a catalog item without duration_seconds still renders the card" do
    catalog = { "pop" => { url: "/demos/genres/pop-v1.mp3", label: "Pop" } }
    Campaigns::GenreSamples.stub(:catalog, catalog) do
      get new_campaign_path
    end
    assert_response :success
    assert_select ".ui-player [data-genre-preview-target=duration]", count: 1
  end

  test "the card carries the illustrative voice note, the direction chips and a recoverable error" do
    get new_campaign_path
    player = player_card
    assert_includes player.text.squish, "Exemplo com voz ilustrativa. Não gasta rodada."
    assert_includes player.text.squish, "Sua direção"
    direction = player.at_css('[data-campaign-form-target="direction"]')
    assert direction, "alvo campaign-form direction com os chips de ritmo · voz · clima"
    assert_equal [ "Pop", "Escolher por mim", "Animado" ], direction.css("li").map { |node| node.text.squish }

    error = card_target(player, "error")
    assert error.key?("hidden")
    assert_includes error.text.squish, "Não foi possível tocar o exemplo"
    retry_button = error.at_css("button[type=button]")
    assert_equal "Tentar de novo", retry_button.text.squish
    assert_includes retry_button["data-action"].to_s.split, "genre-preview#retry"
  end

  test "direction chips follow the saved identity" do
    profile = users(:customer_b2b).business_music_profiles.create!(business_name: "Pizzaria da Vila", musical_genre: "forro",
      vocal_gender: "female", style: "acolhedor")
    get new_campaign_path(music_profile_id: profile.id)
    direction = player_card.at_css('[data-campaign-form-target="direction"]')
    assert direction, "alvo campaign-form direction ausente"
    assert_equal [ "Forró", "Voz feminina", "Acolhedor" ], direction.css("li").map { |node| node.text.squish }
  end

  test "on a genre without a sample the card shows the hint instead of the play button" do
    campaign = Campaign.create!(@attributes.merge(order: orders(:b2b_pending), musical_genre: "auto"))
    get campaign_path(campaign)
    player = player_card
    hint = card_target(player, "hint")
    assert_not hint.key?("hidden")
    assert_equal HINT_AUTO, hint.text.squish
    assert_equal "Escolher por mim", card_target(player, "name").text.squish
  end

  # ---------- ordem no DOM (celular) ----------

  test "inside the step the order is genre tiles, then the player card, then voice, climate and details" do
    get new_campaign_path
    nodes = sound_section.css("*").to_a
    position = ->(node) { nodes.index(node) }
    last_tile = sound_section.css(GENRE_RADIOS).last
    player = sound_section.at_css(".ui-player")
    voice = sound_section.at_css(VOICE_RADIOS)
    climate = sound_section.at_css(STYLE_RADIOS)
    notes = sound_section.at_css("textarea#campaign_music_notes")
    assert player, "o cartão .ui-player precisa estar dentro do passo 2"
    assert_operator position.call(last_tile), :<, position.call(player)
    assert_operator position.call(player), :<, position.call(voice)
    assert_operator position.call(voice), :<, position.call(climate)
    assert_operator position.call(climate), :<, position.call(notes)
  end

  private

  def step_sections
    css_select('form.ui-form section[data-campaign-form-target="step"]')
  end

  def sound_section
    section = step_sections[1]
    assert section, "o passo 2 (segunda section[data-campaign-form-target=step]) não existe"
    section
  end

  def card_target(card, name)
    node = card.at_css(format(PLAYER_TARGET, name))
    assert node, "alvo genre-preview #{name} ausente do cartão"
    node
  end

  def player_card
    card = css_select(".ui-player").first
    assert card, "o cartão .ui-player ainda não existe"
    card
  end

  def checked_values(selector)
    sound_section.css(selector).select { |radio| radio.key?("checked") }.map { |radio| radio["value"] }
  end
end
