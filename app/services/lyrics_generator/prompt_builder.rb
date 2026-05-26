# frozen_string_literal: true

module LyricsGenerator
  class PromptBuilder < BaseService
    PROMPT_VERSION = "v1.0"

    attribute :mode
    attribute :briefing
    attribute :current_lyrics, :string
    attribute :user_feedback, :string

    def call
      mode_sym = mode.to_sym

      if mode_sym == :regen && current_lyrics.blank?
        return failure_result(:missing_current_lyrics)
      end

      success_result({
        prompt:         build_prompt(mode_sym),
        prompt_version: PROMPT_VERSION
      })
    end

    private

    def build_prompt(mode_sym)
      case mode_sym
      when :regen then build_regen_prompt
      else             build_initial_prompt
      end
    end

    def build_initial_prompt
      parts = [
        "You are an expert music lyrics writer.",
        "Write song lyrics based on the following briefing:",
        "Topic: #{briefing.about}",
        "Music style: #{briefing.music_style}",
        "Language: #{briefing.language}"
      ]

      parts << "Recipient: #{briefing.recipient}" if briefing.recipient.present?
      parts << "Mood: #{briefing.mood}"           if briefing.mood.present?
      parts << "Occasion: #{briefing.occasion}"   if briefing.occasion.present?
      parts << "Tempo: #{briefing.tempo}"         if briefing.tempo.present?
      parts << "Keywords: #{briefing.keywords}"   if briefing.keywords.present?
      parts << "Avoid: #{briefing.avoid}"         if briefing.avoid.present?

      parts.join("\n")
    end

    def build_regen_prompt
      parts = [
        "You are an expert music lyrics writer.",
        "Regenerate the following song lyrics based on user feedback:",
        "",
        "Current lyrics:",
        current_lyrics,
        "",
        "Original briefing:",
        "Topic: #{briefing.about}",
        "Music style: #{briefing.music_style}",
        "Language: #{briefing.language}"
      ]

      parts << "Recipient: #{briefing.recipient}" if briefing.recipient.present?
      parts << "Mood: #{briefing.mood}"           if briefing.mood.present?

      if user_feedback.present?
        parts << ""
        parts << "User feedback: #{user_feedback}"
      end

      parts.join("\n")
    end
  end
end
