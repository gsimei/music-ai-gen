# frozen_string_literal: true

require "net/http"
require "json"

module MusicGenerator
  class MurekaFilesUploadClient < BaseService
    UPLOAD_URL = "https://api.mureka.ai/v1/files/upload"

    attribute :file_path, :string
    attribute :purpose,   :string, default: -> { "soundtrack" }

    def call
      return failure_result(:invalid_file_size) unless File.size(file_path).between?(1, SoundtrackInput::MAX_FILE_SIZE)
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

      req = Net::HTTP::Post.new(uri.path)
      req["Authorization"] = "Bearer #{ENV.fetch('MUREKA_API_KEY', '')}"
      boundary = "RubyFormBoundary#{SecureRandom.hex(8)}"
      extension = File.extname(file_path)
      filename = "soundtrack#{SoundtrackInput::EXTENSIONS.value?(extension) ? extension : '.bin'}"
      Tempfile.create([ "mureka-upload", ".multipart" ], binmode: true) do |body|
        body.write("--#{boundary}\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\n#{purpose}\r\n")
        body.write("--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\nContent-Type: application/octet-stream\r\n\r\n")
        File.open(file_path, "rb") { |file| IO.copy_stream(file, body) }
        body.write("\r\n--#{boundary}--\r\n")
        body.rewind
        req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
        req.content_length = body.size
        req.body_stream = body
        http.request(req)
      end
    end
  end
end
