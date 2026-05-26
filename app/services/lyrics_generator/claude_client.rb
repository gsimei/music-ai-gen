# frozen_string_literal: true

require "net/http"
require "json"

module LyricsGenerator
  class ClaudeClient < BaseService
    ANTHROPIC_API_URL        = "https://api.anthropic.com/v1/messages"
    MODEL                    = "claude-opus-4-7"
    ANTHROPIC_VERSION        = "2023-06-01"
    INPUT_PRICE_PER_MILLION  = 15.0
    OUTPUT_PRICE_PER_MILLION = 75.0

    attribute :system_prompt, :string
    attribute :user_prompt, :string
    attribute :prompt_version, :string

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response   = post_to_anthropic
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).to_i

      return failure_result(:api_error) unless response.code.to_i == 200

      body     = JSON.parse(response.body)
      raw_text = body.dig("content", 0, "text").to_s

      parsed_json   = JSON.parse(raw_text)
      input_tokens  = body.dig("usage", "input_tokens").to_i
      output_tokens = body.dig("usage", "output_tokens").to_i
      cost_usd      = (input_tokens * INPUT_PRICE_PER_MILLION + output_tokens * OUTPUT_PRICE_PER_MILLION) / 1_000_000.0

      success_result({
        parsed_json:   parsed_json,
        input_tokens:  input_tokens,
        output_tokens: output_tokens,
        cost_usd:      cost_usd,
        raw_response:  response.body,
        model:         body["model"].presence || MODEL,
        latency_ms:    latency_ms
      })
    rescue JSON::ParserError
      failure_result(:invalid_json)
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure_result(:timeout)
    rescue StandardError
      failure_result(:unexpected_error)
    end

    private

    def post_to_anthropic
      uri  = URI(ANTHROPIC_API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 120
      http.open_timeout = 10

      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"]      = "application/json"
      req["x-api-key"]         = ENV.fetch("ANTHROPIC_API_KEY", "")
      req["anthropic-version"] = ANTHROPIC_VERSION

      req.body = JSON.generate({
        model:      MODEL,
        max_tokens: 4096,
        system:     system_prompt,
        messages:   [{ role: "user", content: user_prompt }]
      })

      http.request(req)
    end
  end
end
