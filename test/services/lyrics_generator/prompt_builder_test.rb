# frozen_string_literal: true

require "test_helper"

# Tests for LyricsGenerator::PromptBuilder
#
# Responsibilities:
# - Builds prompts for three modes: :initial, :refine, :regen
# - Interpolates briefing fields into the prompt text
# - Does NOT interpolate the literal string "nil" when optional fields are absent
# - Returns failure_result when :regen mode is called without current_lyrics
# - Exposes PROMPT_VERSION constant as a non-empty string "v1.0"
#
# Service interface:
#   LyricsGenerator::PromptBuilder.call(
#     mode:           :initial | :refine | :regen,
#     briefing:       Briefing instance,
#     current_lyrics: String | nil,   # required for :regen
#     user_feedback:  String | nil
#   )
#
# Returns ServiceResult:
#   success? => true,  value: { prompt: String, prompt_version: String }
#   success? => false, errors: Symbol (e.g. :missing_current_lyrics)
class LyricsGenerator::PromptBuilderTest < ActiveSupport::TestCase
  test "unnamed campaigns focus on the offer and never request an invented business name" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.assign_attributes(recipient: nil, about: "Promoção: Casa com 03 quartos por R$ 750.000.", keywords: nil, extra_params: { "campaign" => true })
    [ :initial, :regen ].each do |mode|
      result = LyricsGenerator::PromptBuilder.call(mode: mode, briefing: briefing, current_lyrics: "Uma casa para você")
      assert result.success?
      assert_includes result.value[:prompt], "No business name was provided"
      assert_includes result.value[:prompt], "Do not invent a company name"
      assert_includes result.value[:prompt], briefing.about
      refute_includes result.value[:prompt], "Business:"
      refute_includes result.value[:prompt], "repeat the business name"
    end
  end

  test "a campaign revision receives the original conditions even when the previous lyrics omitted them" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.about = "Café com 10% de desconto, terça a quinta, somente para consumir no local."
    briefing.extra_params = { "campaign" => true }
    result = LyricsGenerator::PromptBuilder.call(mode: :regen, briefing: briefing,
      current_lyrics: "Venha ao café!", user_feedback: "Deixe mais animado")
    assert result.success?
    assert_includes result.value[:prompt], briefing.about
    assert_includes result.value[:prompt], "Offer accuracy takes priority"
  end

  # ---------------------------------------------------------------------------
  # PROMPT_VERSION constant
  # ---------------------------------------------------------------------------

  test "PROMPT_VERSION is defined as a non-empty string" do
    assert_equal "v2.2", LyricsGenerator::PromptBuilder::PROMPT_VERSION
  end

  test "PROMPT_VERSION is a String" do
    assert_kind_of String, LyricsGenerator::PromptBuilder::PROMPT_VERSION
    assert_not LyricsGenerator::PromptBuilder::PROMPT_VERSION.empty?
  end

  # ---------------------------------------------------------------------------
  # mode :initial — happy path with full briefing
  # ---------------------------------------------------------------------------

  test "mode :initial with complete briefing returns success" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "mode :initial result value contains prompt_version v1.0" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_equal "v2.2", result.value[:prompt_version]
  end

  test "mode :initial result value contains prompt string" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_kind_of String, result.value[:prompt]
    assert_not result.value[:prompt].empty?
  end

  test "mode :initial prompt includes briefing about field" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:prompt], briefing.about
  end

  test "mode :initial prompt includes music_style" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:prompt], briefing.music_style
  end

  test "mode :initial prompt includes language" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:prompt], briefing.language
  end

  test "mode :initial prompt includes recipient when present" do
    briefing = briefings(:b2b_paid_briefing)
    assert_equal "Maria", briefing.recipient

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:prompt], "Maria"
  end

  test "mode :initial prompt includes mood when present" do
    briefing = briefings(:b2b_paid_briefing)
    assert_equal "happy", briefing.mood

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:prompt], "happy"
  end

  # ---------------------------------------------------------------------------
  # mode :initial — optional fields nil — no "nil" interpolation
  # ---------------------------------------------------------------------------

  test "mode :initial with nil optional fields does not contain literal nil in prompt" do
    briefing = briefings(:b2b_paid_no_optional_briefing)
    assert_nil briefing.recipient
    assert_nil briefing.mood
    assert_nil briefing.occasion

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    refute_includes result.value[:prompt], "nil"
  end

  test "mode :initial without optional fields still returns success" do
    briefing = briefings(:b2b_paid_no_optional_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
  end

  # ---------------------------------------------------------------------------
  # mode :regen — failure when current_lyrics missing
  # ---------------------------------------------------------------------------

  test "mode :regen without current_lyrics returns failure" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: nil
    )

    assert result.failure?, "Expected failure when current_lyrics is nil"
  end

  test "mode :regen without current_lyrics returns :missing_current_lyrics error" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: nil
    )

    assert result.failure?
    assert_includes result.errors.to_s, "current_lyrics"
  end

  test "mode :regen without current_lyrics key (not passed) returns failure" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :regen,
      briefing: briefing
    )

    assert result.failure?
  end

  # ---------------------------------------------------------------------------
  # mode :regen — success with current_lyrics and user_feedback
  # ---------------------------------------------------------------------------

  test "mode :regen with current_lyrics and user_feedback returns success" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma",
      user_feedback:  "Piu romantica per favore"
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "mode :regen prompt includes current_lyrics content" do
    briefing       = briefings(:b2b_paid_briefing)
    current_lyrics = "Buon compleanno cara mamma"

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: current_lyrics,
      user_feedback:  "Piu romantica"
    )

    assert result.success?
    assert_includes result.value[:prompt], current_lyrics
  end

  test "mode :regen prompt includes user_feedback" do
    briefing      = briefings(:b2b_paid_briefing)
    user_feedback = "Piu romantica per favore"

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma",
      user_feedback:  user_feedback
    )

    assert result.success?
    assert_includes result.value[:prompt], user_feedback
  end

  test "mode :regen with current_lyrics but nil user_feedback returns success" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma",
      user_feedback:  nil
    )

    assert result.success?
    refute_includes result.value[:prompt], "nil"
  end

  test "mode :regen result includes prompt_version" do
    briefing = briefings(:b2b_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma"
    )

    assert result.success?
    assert_equal "v2.2", result.value[:prompt_version]
  end

  # ---------------------------------------------------------------------------
  # Short-form constraint (duration <= 60s)
  # ---------------------------------------------------------------------------

  test "mode :initial with duration <= 60 includes short-form structure constraint" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.target_duration_seconds = 30

    result = LyricsGenerator::PromptBuilder.call(mode: :initial, briefing: briefing)

    assert result.success?
    assert_includes result.value[:prompt], "Maximum 30 words total"
    assert_includes result.value[:prompt], "No intro, no bridge, no outro"
  end

  test "mode :initial with duration exactly 60 includes short-form constraint" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.target_duration_seconds = 60

    result = LyricsGenerator::PromptBuilder.call(mode: :initial, briefing: briefing)

    assert result.success?
    assert_includes result.value[:prompt], "Maximum 30 words total"
  end

  test "mode :initial with duration > 60 does NOT include short-form constraint" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.target_duration_seconds = 90

    result = LyricsGenerator::PromptBuilder.call(mode: :initial, briefing: briefing)

    assert result.success?
    refute_includes result.value[:prompt], "Maximum 30 words total"
    refute_includes result.value[:prompt], "No intro, no bridge, no outro"
  end

  test "mode :regen with duration <= 60 includes short-form constraint" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.target_duration_seconds = 30

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Test lyrics"
    )

    assert result.success?
    assert_includes result.value[:prompt], "Keep it SHORT"
    assert_includes result.value[:prompt], "30 words total"
  end

  test "mode :regen with duration > 60 does NOT include short-form constraint" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.target_duration_seconds = 90

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Test lyrics"
    )

    assert result.success?
    refute_includes result.value[:prompt], "Keep it SHORT"
  end

  # ---------------------------------------------------------------------------
  # structure_hint — mode :initial
  # ---------------------------------------------------------------------------

  test "mode :initial with structure_hint present includes 'Preferred structure:' line in prompt" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.structure_hint = "Verse - Chorus - Verse - Chorus - Bridge - Chorus"

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:prompt], "Preferred structure:"
    assert_includes result.value[:prompt], "Verse - Chorus - Verse - Chorus - Bridge - Chorus"
  end

  test "mode :initial with blank structure_hint does NOT include 'Preferred structure:' in prompt" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.structure_hint = ""

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    refute_includes result.value[:prompt], "Preferred structure:"
  end

  test "mode :initial with nil structure_hint does NOT include 'Preferred structure:' in prompt" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.structure_hint = nil

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    refute_includes result.value[:prompt], "Preferred structure:"
  end

  # ---------------------------------------------------------------------------
  # structure_hint — mode :regen
  # ---------------------------------------------------------------------------

  test "mode :regen with structure_hint present includes structure in prompt" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.structure_hint = "Intro - Verse - Chorus"

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma"
    )

    assert result.success?
    assert_includes result.value[:prompt], "Intro - Verse - Chorus"
  end

  test "mode :regen with nil structure_hint does NOT include 'Song structure:' in prompt" do
    briefing = briefings(:b2b_paid_briefing)
    briefing.structure_hint = nil

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma"
    )

    assert result.success?
    refute_includes result.value[:prompt], "Song structure:"
  end
end
