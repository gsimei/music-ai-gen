# frozen_string_literal: true

require "net/http"
require "json"

module MusicGenerator
  class MurekaFilesUploadClient < BaseService
    UPLOAD_URL = "https://api.mureka.ai/v1/files/upload"

    attribute :file_path, :string
    attribute :purpose,   :string, default: -> { "soundtrack" }

    def call
      response = post_to_mureka
      return failure_result(:api_error) unless response.code.to_i == 200

      body    = JSON.parse(response.body)
      file_id = body["id"]

      return failure_result(:missing_file_id) if file_id.blank?

      success_result({ file_id: file_id, status: body["status"] })
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure_result(:timeout)
    rescue SocketError, StandardError
      failure_result(:unexpected_error)
    end

    private

    def post_to_mureka
      uri  = URI(UPLOAD_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 120
      http.open_timeout = 10

      boundary = "RubyFormBoundary#{SecureRandom.hex(8)}"

      req = Net::HTTP::Post.new(uri.path)
      req["Authorization"] = "Bearer #{ENV.fetch('MUREKA_API_KEY', '')}"
      req["Content-Type"]  = "multipart/form-data; boundary=#{boundary}"
      req.body             = build_multipart_body(boundary)

      http.request(req)
    end

    def build_multipart_body(boundary)
      file_content = File.binread(file_path)
      filename     = File.basename(file_path)

      body = String.new(encoding: "ASCII-8BIT")
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n"
      body << "#{purpose}\r\n"
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n"
      body << "Content-Type: application/octet-stream\r\n\r\n"
      body << file_content
      body << "\r\n--#{boundary}--\r\n"
      body
    end
  end
end
