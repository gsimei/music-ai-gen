# frozen_string_literal: true

require "net/http"
require "json"

module MusicGenerator
  class MurekaClient < BaseService
    MUREKA_SONG_URL = "https://api.mureka.ai/v1/song/generate"

    attribute :prompt,      :string
    attribute :lyrics,      :string
    attribute :voice_id,    :string
    attribute :melody_hint, :string
    attribute :model, :string, default: "auto"
    attribute :n, :integer, default: 2
    attribute :gender, :string

    def call
      return failure_result(:invalid_gender) if gender.present? && !%w[female male].include?(gender)
      response = post_to_mureka
      return api_failure(response) unless response.code.to_i == 200

      body   = JSON.parse(response.body)
      job_id = body["id"]

      return failure_result(:missing_job_id) if job_id.blank?

      success_result({ job_id: job_id })
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure_result(:timeout)
    rescue SocketError, StandardError
      failure_result(:unexpected_error)
    end

    private

    def api_failure(response)
      status = response.code.to_i
      body = JSON.parse(response.body) rescue {}
      message = body.is_a?(Hash) ? body["error"].to_s.downcase : ""
      kind = if status == 429
        message.match?(/quota|credit|balance|billing|insufficient/) ? "quota_exhausted" : "rate_limited"
      elsif [400, 401, 403, 422].include?(status)
        "request_rejected"
      else
        "submission_uncertain"
      end
      delay = Integer(response["Retry-After"], exception: false)
      ServiceResult.new(success: false, errors: :api_error,
        value: { failure_kind: kind, http_status: status, retry_after: delay && delay.clamp(5, 300), trace_id: body.is_a?(Hash) ? body["trace_id"] : nil })
    end

    def post_to_mureka
      uri  = URI(MUREKA_SONG_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 120
      http.open_timeout = 10

      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{ENV.fetch('MUREKA_API_KEY', '')}"

      effective_prompt = [ prompt, melody_hint ].reject(&:blank?).join(". ")
      body = { "model" => model, "n" => n, "prompt" => effective_prompt }
      body["lyrics"]   = lyrics   if lyrics.present?
      body["gender"] = gender if gender.present?
      body["voice_id"] = voice_id if voice_id.present?

      req.body = JSON.generate(body)

      http.request(req)
    end
  end
end
