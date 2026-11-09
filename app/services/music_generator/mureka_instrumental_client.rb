# frozen_string_literal: true

require "net/http"
require "json"

module MusicGenerator
  class MurekaInstrumentalClient < BaseService
    MUREKA_INSTRUMENTAL_URL = "https://api.mureka.ai/v1/instrumental/generate"

    attribute :prompt, :string

    def call
      response = post_to_mureka
      return failure_result(:api_error) unless response.code.to_i == 200

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

    def post_to_mureka
      uri  = URI(MUREKA_INSTRUMENTAL_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 120
      http.open_timeout = 10

      req = Net::HTTP::Post.new(uri.path)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{ENV.fetch('MUREKA_API_KEY', '')}"
      req.body = JSON.generate({ "model" => "auto", "prompt" => prompt.to_s, "n" => 2 })

      http.request(req)
    end
  end
end
