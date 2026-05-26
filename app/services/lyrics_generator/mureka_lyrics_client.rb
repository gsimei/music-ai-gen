# frozen_string_literal: true

require "net/http"
require "json"

module LyricsGenerator
  class MurekaLyricsClient < BaseService
    MUREKA_LYRICS_URL = "https://api.mureka.ai/v1/lyrics/generate"

    attribute :prompt, :string

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response   = post_to_mureka
      latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).to_i

      return failure_result(:api_error) unless response.code.to_i == 200

      body   = JSON.parse(response.body)
      title  = body["title"].to_s
      lyrics = body["lyrics"].to_s

      return failure_result(:missing_fields) if title.blank? || lyrics.blank?

      success_result({
        title:        title,
        lyrics:       lyrics,
        raw_response: response.body,
        latency_ms:   latency_ms
      })
    rescue JSON::ParserError
      failure_result(:invalid_json)
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure_result(:timeout)
    rescue StandardError
      failure_result(:unexpected_error)
    end

    private

    def post_to_mureka
      uri  = URI(MUREKA_LYRICS_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 120
      http.open_timeout = 10

      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"]   = "application/json"
      req["Authorization"]  = "Bearer #{ENV.fetch('MUREKA_API_KEY', '')}"

      req.body = JSON.generate({ "prompt" => prompt })

      http.request(req)
    end
  end
end
