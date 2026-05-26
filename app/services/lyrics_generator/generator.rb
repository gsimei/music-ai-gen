# frozen_string_literal: true

module LyricsGenerator
  class Generator < BaseService
    attribute :order
    attribute :mode
    attribute :parent_draft_id
    attribute :user_feedback, :string

    def call
      mode_sym = mode.to_sym
      briefing = order.briefing
      return failure_result(:no_briefing) unless briefing

      parent_draft = nil

      if mode_sym == :regen
        return failure_result(:regen_limit_reached) if regen_limit_reached?

        parent_draft = parent_draft_id.present? ? LyricsDraft.find_by(id: parent_draft_id) : nil
        return failure_result(:invalid_parent_draft) if parent_draft.nil?
      end

      prompt_result = PromptBuilder.call(
        mode:           mode_sym,
        briefing:       briefing,
        current_lyrics: parent_draft&.content,
        user_feedback:  user_feedback
      )
      return failure_result(prompt_result.errors) unless prompt_result.success?

      claude_result = ClaudeClient.call(
        system_prompt:  prompt_result.value[:system_prompt],
        user_prompt:    prompt_result.value[:user_prompt],
        prompt_version: prompt_result.value[:prompt_version]
      )

      if claude_result.failure?
        record_generation_job(
          order:          order,
          step:           step_for(mode_sym),
          status:         "failed",
          prompt_version: prompt_result.value[:prompt_version],
          lyrics_draft:   nil,
          api_result:     nil
        )
        return failure_result(claude_result.errors)
      end

      draft = build_and_save_draft(mode_sym, parent_draft, claude_result.value, prompt_result.value[:prompt_version])
      return failure_result(draft.errors) unless draft.persisted?

      order.increment!(:lyrics_regen_used) if mode_sym == :regen

      record_generation_job(
        order:          order,
        step:           step_for(mode_sym),
        status:         "success",
        prompt_version: prompt_result.value[:prompt_version],
        lyrics_draft:   draft,
        api_result:     claude_result.value
      )

      success_result(draft)
    end

    private

    def regen_limit_reached?
      order.lyrics_regen_used >= order.lyrics_regen_limit
    end

    def step_for(mode_sym)
      mode_sym == :regen ? "lyrics_regen" : "lyrics_initial"
    end

    def build_and_save_draft(mode_sym, parent_draft, api_result, prompt_version)
      next_version = (order.lyrics_drafts.maximum(:version) || 0) + 1
      content      = extract_text_content(api_result[:parsed_json])

      attrs = {
        order:          order,
        version:        next_version,
        source:         mode_sym == :regen ? "regenerated" : "ai_generated",
        content:        content,
        structure:      api_result[:parsed_json],
        prompt_version: prompt_version,
        llm_model:      api_result[:model],
        llm_provider:   "anthropic",
        input_tokens:   api_result[:input_tokens],
        output_tokens:  api_result[:output_tokens],
        latency_ms:     api_result[:latency_ms]
      }

      if mode_sym == :regen
        attrs[:parent_draft_id] = parent_draft&.id
        attrs[:user_feedback]   = user_feedback
      end

      LyricsDraft.create(attrs)
    end

    def extract_text_content(parsed_json)
      sections = parsed_json["sections"] || []
      lines    = sections.flat_map { |s| s["lines"] || [] }
      lines.join("\n").presence || parsed_json.to_json
    end

    def record_generation_job(order:, step:, status:, prompt_version:, lyrics_draft:, api_result:)
      attrs = {
        order:          order,
        step:           step,
        status:         status,
        provider:       "anthropic",
        model:          ClaudeClient::MODEL,
        prompt_version: prompt_version,
        lyrics_draft:   lyrics_draft,
        finished_at:    Time.current
      }

      if api_result
        attrs.merge!(
          input_tokens:  api_result[:input_tokens],
          output_tokens: api_result[:output_tokens],
          cost_usd:      api_result[:cost_usd],
          latency_ms:    api_result[:latency_ms]
        )
      end

      GenerationJob.create(attrs)
    end
  end
end
