# frozen_string_literal: true

require "net/http"
require "json"

module MusicGenerator
  class MurekaStatusClient < BaseService
    MUREKA_STATUS_BASE_URL = "https://api.mureka.ai/v1/song/query"

    attribute :job_id, :string

    def call
      response = get_from_mureka
      return failure_result(:api_error) unless response.code.to_i == 200

      body   = JSON.parse(response.body)
      status = body["status"]

      case status
      when "succeeded"
        choices = map_choices(body["choices"] || [])
        success_result({ status: "succeeded", choices: choices })
      when "failed", "timeouted", "cancelled"
        success_result({ status: "failed", choices: nil })
      else
        # "pending" and any other interim state
        success_result({ status: "pending", choices: nil })
      end
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure_result(:timeout)
    rescue SocketError, StandardError
      failure_result(:unexpected_error)
    end

    private

    def get_from_mureka
      uri  = URI("#{MUREKA_STATUS_BASE_URL}/#{job_id}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 30
      http.open_timeout = 10

      req = Net::HTTP::Get.new(uri.path)
      req["Authorization"] = "Bearer #{ENV.fetch('MUREKA_API_KEY', '')}"

      http.request(req)
    end

    def map_choices(choices)
      choices.map do |choice|
        {
          url:             choice["url"],
          flac_url:        choice["flac_url"],
          wav_url:         choice["wav_url"],
          duration_ms:     choice["duration"],
          lyrics_sections: choice["lyrics_sections"] || []
        }
      end
    end
  end
end
