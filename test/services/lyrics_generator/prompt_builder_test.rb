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
#   success? => true,  value: { system_prompt: String, user_prompt: String, prompt_version: String }
#   success? => false, errors: Symbol (e.g. :missing_current_lyrics)
class LyricsGenerator::PromptBuilderTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # PROMPT_VERSION constant
  # ---------------------------------------------------------------------------

  test "PROMPT_VERSION is defined as a non-empty string" do
    assert_equal "v1.0", LyricsGenerator::PromptBuilder::PROMPT_VERSION
  end

  test "PROMPT_VERSION is a String" do
    assert_kind_of String, LyricsGenerator::PromptBuilder::PROMPT_VERSION
    assert_not LyricsGenerator::PromptBuilder::PROMPT_VERSION.empty?
  end

  # ---------------------------------------------------------------------------
  # mode :initial — happy path with full briefing
  # ---------------------------------------------------------------------------

  test "mode :initial with complete briefing returns success" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "mode :initial result value contains prompt_version v1.0" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_equal "v1.0", result.value[:prompt_version]
  end

  test "mode :initial result value contains system_prompt string" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_kind_of String, result.value[:system_prompt]
    assert_not result.value[:system_prompt].empty?
  end

  test "mode :initial result value contains user_prompt string" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_kind_of String, result.value[:user_prompt]
    assert_not result.value[:user_prompt].empty?
  end

  test "mode :initial user_prompt includes briefing about field" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:user_prompt], briefing.about
  end

  test "mode :initial user_prompt includes music_style" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:user_prompt], briefing.music_style
  end

  test "mode :initial user_prompt includes language" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:user_prompt], briefing.language
  end

  test "mode :initial user_prompt includes recipient when present" do
    briefing = briefings(:b2c_paid_briefing)
    assert_equal "Maria", briefing.recipient

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:user_prompt], "Maria"
  end

  test "mode :initial user_prompt includes mood when present" do
    briefing = briefings(:b2c_paid_briefing)
    assert_equal "happy", briefing.mood

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    assert_includes result.value[:user_prompt], "happy"
  end

  # ---------------------------------------------------------------------------
  # mode :initial — optional fields nil — no "nil" interpolation
  # ---------------------------------------------------------------------------

  test "mode :initial with nil optional fields does not contain literal nil in prompt" do
    briefing = briefings(:b2c_paid_no_optional_briefing)
    assert_nil briefing.recipient
    assert_nil briefing.mood
    assert_nil briefing.occasion

    result = LyricsGenerator::PromptBuilder.call(
      mode:     :initial,
      briefing: briefing
    )

    assert result.success?
    # The prompts must not contain the literal string "nil"
    refute_includes result.value[:user_prompt], "nil"
    refute_includes result.value[:system_prompt], "nil"
  end

  test "mode :initial without optional fields still returns success" do
    briefing = briefings(:b2c_paid_no_optional_briefing)

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
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: nil
    )

    assert result.failure?, "Expected failure when current_lyrics is nil"
  end

  test "mode :regen without current_lyrics returns :missing_current_lyrics error" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: nil
    )

    assert result.failure?
    # Errors should communicate the specific cause
    assert_includes result.errors.to_s, "current_lyrics"
  end

  test "mode :regen without current_lyrics key (not passed) returns failure" do
    briefing = briefings(:b2c_paid_briefing)

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
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma",
      user_feedback:  "Piu romantica per favore"
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "mode :regen prompt includes current_lyrics content" do
    briefing       = briefings(:b2c_paid_briefing)
    current_lyrics = "Buon compleanno cara mamma"

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: current_lyrics,
      user_feedback:  "Piu romantica"
    )

    assert result.success?
    assert_includes result.value[:user_prompt], current_lyrics
  end

  test "mode :regen prompt includes user_feedback" do
    briefing       = briefings(:b2c_paid_briefing)
    user_feedback  = "Piu romantica per favore"

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma",
      user_feedback:  user_feedback
    )

    assert result.success?
    assert_includes result.value[:user_prompt], user_feedback
  end

  test "mode :regen with current_lyrics but nil user_feedback returns success" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma",
      user_feedback:  nil
    )

    assert result.success?
    refute_includes result.value[:user_prompt], "nil"
  end

  test "mode :regen result includes prompt_version" do
    briefing = briefings(:b2c_paid_briefing)

    result = LyricsGenerator::PromptBuilder.call(
      mode:           :regen,
      briefing:       briefing,
      current_lyrics: "Buon compleanno cara mamma"
    )

    assert result.success?
    assert_equal "v1.0", result.value[:prompt_version]
  end
end
