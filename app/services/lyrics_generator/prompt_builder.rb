# frozen_string_literal: true

module LyricsGenerator
  class PromptBuilder < BaseService
    PROMPT_VERSION = "v2.2"

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

    def duration_seconds
      briefing.target_duration_seconds.presence || 60
    end

    def short_form?
      duration_seconds.to_i <= 60
    end

    def visual_context
      briefing.extra_params&.dig("visual_context").presence ||
        briefing.extra_params&.dig(:visual_context).presence
    end

    def build_initial_prompt
      business_name = provided_business_name
      use_case = briefing.occasion.presence || "social media"

      lines = []

      if short_form?
        lines << "Write a #{duration_seconds}-second commercial jingle. STRUCTURE: [Verse] (2 lines) + [Chorus] (2–3 lines). Maximum 30 words total. No intro, no bridge, no outro."
      else
        lines << "Write a #{duration_seconds}-second commercial jingle. STRUCTURE: [Verse] + [Chorus] + [Verse] + [Chorus]."
        lines << (briefing.structure_hint.present? ? "Preferred structure: #{briefing.structure_hint}." : nil)
      end

      lines << (business_name ? "Business: #{business_name} — #{use_case}." : "No business name was provided. Do not invent a company name. Focus on the offer. Use case: #{use_case}.")
      lines << "About: #{briefing.about}" if briefing.about.present?
      lines << campaign_accuracy_rules
      lines << "Language: #{briefing.language}. Style: #{briefing.music_style}."
      lines << "Use natural Brazilian Portuguese. Preserve the exact business name and offer; never invent discounts, prices or claims." if briefing.language == "pt"
      lines << "Mood: #{briefing.mood}." if briefing.mood.present?
      lines << "Tempo: #{briefing.tempo}." if briefing.tempo.present?
      lines << "Include keywords: #{briefing.keywords}." if briefing.keywords.present?
      lines << "Avoid: #{briefing.avoid}." if briefing.avoid.present?
      lines << "Visual context: #{visual_context}." if visual_context.present?
      lines << (business_name ? "Rules: hook-first, repeat the business name at least twice, clear rhyme scheme, no generic filler." : "Rules: hook-first, clear rhyme scheme, no generic filler.")

      lines.compact.join(" ").strip
    end

    def build_regen_prompt
      business_name = provided_business_name

      lines = []

      lines << "Rewrite the following jingle based on the feedback below."
      lines << (short_form? ? "Keep it SHORT: #{duration_seconds}s, 1 verse + 1 chorus, 30 words total." : "Target duration: #{duration_seconds} seconds.")
      lines << "Feedback: #{user_feedback.present? ? user_feedback : 'Make it more memorable and catchy.'}"
      lines << (business_name ? "Business: #{business_name}." : "No business name was provided. Do not invent a company name; focus on the offer.")
      lines << "Style: #{briefing.music_style}. Language: #{briefing.language}."
      lines << "Original business and offer: #{briefing.about}" if briefing.about.present?
      lines << campaign_accuracy_rules
      lines << "Structure: #{briefing.structure_hint}." if briefing.structure_hint.present?
      lines << "Visual context: #{visual_context}." if visual_context.present?
      lines << ""
      lines << "Current lyrics:"
      lines << current_lyrics

      lines.compact.join("\n").strip
    end

    def campaign_accuracy_rules
      return unless briefing.extra_params&.dig("campaign")

      "Offer accuracy takes priority over rhyme and repeated slogans. Preserve the discount, its meaning, eligible products, days, time limits and restrictions such as dine-in or pickup. Never turn a discount into a prize or reward. Keep these details near the beginning so they fit in the short video. Remove decorative phrases rather than offer conditions. Do not invent freshness, quality or other claims."
    end

    def provided_business_name
      return if briefing.extra_params&.dig("campaign") && briefing.recipient.blank?
      briefing.recipient.presence || briefing.about.to_s.truncate(40)
    end
  end
end
