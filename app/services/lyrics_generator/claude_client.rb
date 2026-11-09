# frozen_string_literal: true

module LyricsGenerator
  class ClaudeClient
    MODEL = "gpt-4o-mini"

    def self.chat(system:, messages:, order: nil)
      new.chat(system: system, messages: messages, order: order)
    end

    MAX_RETRIES = 2

    def chat(system:, messages:, order: nil)
      client        = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
      full_messages = [ { role: "system", content: system } ] + messages
      params        = {
        model:           MODEL,
        messages:        full_messages,
        max_tokens:      2048,
        response_format: { type: "json_object" }
      }

      MAX_RETRIES.times do |attempt|
        cost = GenerationCost.record!(order: order, operation: "chat", provider: "openai", model: MODEL) if order&.campaign
        response = client.chat(parameters: params)
        if cost && (usage = response["usage"]).present?
          input = usage.fetch("prompt_tokens", 0)
          cached = usage.dig("prompt_tokens_details", "cached_tokens").to_i
          output = usage.fetch("completion_tokens", 0)
          usd = ((input - cached) * BigDecimal("0.15") + cached * BigDecimal("0.075") + output * BigDecimal("0.60")) / 1_000_000
          cost.update!(estimated_usd: usd, estimated_brl: usd * cost.usd_brl, status: "estimated",
            usage: usage, provider_request_id: response["id"])
        end
        content  = response.dig("choices", 0, "message", "content").to_s.strip

        if content.present?
          return { content: content }
        end

        finish_reason = response.dig("choices", 0, "finish_reason")
        Rails.logger.warn "[LyricsGenerator::ClaudeClient] Empty content on attempt #{attempt + 1}, finish_reason=#{finish_reason}"
      end

      raise "OpenAI returned empty content after #{MAX_RETRIES} attempts"
    rescue StandardError => e
      Rails.logger.error "[LyricsGenerator::ClaudeClient] API error: #{e.message}"
      raise
    end
  end
end
