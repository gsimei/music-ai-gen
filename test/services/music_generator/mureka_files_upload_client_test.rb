# frozen_string_literal: true

require "test_helper"
require "tempfile"

module MusicGenerator; end unless defined?(MusicGenerator)

class MusicGenerator::MurekaFilesUploadClientTest < ActiveSupport::TestCase
  UPLOAD_URL = "https://api.mureka.ai/v1/files/upload"

  SUCCESS_BODY = JSON.generate({ "id" => "mureka_file_abc123", "status" => "pending" })

  def with_temp_file(content: "binary video data", ext: ".mp4")
    Tempfile.create([ "test_soundtrack", ext ], binmode: true) do |f|
      f.write(content)
      f.flush
      yield f.path
    end
  end

  def stub_success(body: SUCCESS_BODY)
    stub_request(:post, UPLOAD_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body)
  end

  def stub_api_error
    stub_request(:post, UPLOAD_URL)
      .to_return(status: 422, headers: { "Content-Type" => "application/json" },
                 body: JSON.generate({ "error" => "bad request" }))
  end

  def stub_timeout
    stub_request(:post, UPLOAD_URL).to_timeout
  end

  def stub_socket_error
    stub_request(:post, UPLOAD_URL).to_raise(SocketError)
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  test "returns success with file_id on HTTP 200" do
    stub_success
    with_temp_file do |path|
      result = MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      assert result.success?
      assert_equal "mureka_file_abc123", result.value[:file_id]
    end
  end

  test "result includes status from response" do
    stub_success
    with_temp_file do |path|
      result = MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      assert_equal "pending", result.value[:status]
    end
  end

  test "sends Authorization header" do
    stub_success
    ClimateControl.modify(MUREKA_API_KEY: "test-upload-key") do
      with_temp_file do |path|
        MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      end
    end
    assert_requested(:post, UPLOAD_URL,
                     headers: { "Authorization" => "Bearer test-upload-key" })
  end

  test "sends multipart Content-Type header" do
    stub_success
    with_temp_file do |path|
      MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
    end
    assert_requested(:post, UPLOAD_URL) do |req|
      req.headers["Content-Type"].start_with?("multipart/form-data")
    end
  end

  test "request body includes purpose field" do
    stub_success
    with_temp_file do |path|
      MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
    end
    assert_requested(:post, UPLOAD_URL) do |req|
      req.body.include?("soundtrack")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure paths
  # ---------------------------------------------------------------------------

  test "returns failure :api_error on non-200 response" do
    stub_api_error
    with_temp_file do |path|
      result = MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      assert result.failure?
      assert_equal :api_error, result.errors
    end
  end

  test "returns failure :timeout on network timeout" do
    stub_timeout
    with_temp_file do |path|
      result = MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      assert result.failure?
      assert_equal :timeout, result.errors
    end
  end

  test "returns failure :missing_file_id when 200 response has no id field" do
    stub_success(body: JSON.generate({ "status" => "pending" }))
    with_temp_file do |path|
      result = MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      assert result.failure?
      assert_equal :missing_file_id, result.errors
    end
  end

  test "returns failure :unexpected_error on SocketError" do
    stub_socket_error
    with_temp_file do |path|
      result = MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
      assert result.failure?
      assert_equal :unexpected_error, result.errors
    end
  end

  test "does not raise on any error path" do
    with_temp_file do |path|
      [ -> { stub_api_error }, -> { stub_timeout }, -> { stub_socket_error } ].each do |setup|
        setup.call
        assert_nothing_raised do
          MusicGenerator::MurekaFilesUploadClient.call(file_path: path, purpose: "soundtrack")
        end
      end
    end
  end
end
