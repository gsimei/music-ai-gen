# frozen_string_literal: true

require "test_helper"

module MusicGenerator; end unless defined?(MusicGenerator)

class MusicGenerator::MurekaSoundtrackClientTest < ActiveSupport::TestCase
  SOUNDTRACK_URL = "https://api.mureka.ai/v1/soundtrack/generate"

  SUCCESS_BODY = JSON.generate({ "id" => "job_st_abc123", "status" => "pending" })

  def stub_success(body: SUCCESS_BODY)
    stub_request(:post, SOUNDTRACK_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body)
  end

  def stub_api_error(status: 422)
    stub_request(:post, SOUNDTRACK_URL)
      .to_return(status: status, headers: { "Content-Type" => "application/json" },
                 body: JSON.generate({ "error" => "error" }))
  end

  def stub_timeout
    stub_request(:post, SOUNDTRACK_URL).to_timeout
  end

  def stub_socket_error
    stub_request(:post, SOUNDTRACK_URL).to_raise(SocketError)
  end

  # ---------------------------------------------------------------------------
  # Happy path
  # ---------------------------------------------------------------------------

  test "returns success on HTTP 200 with job id" do
    stub_success
    result = MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "upbeat jingle"
    )
    assert result.success?
    assert_equal "job_st_abc123", result.value[:job_id]
  end

  test "sends Authorization header" do
    stub_success
    ClimateControl.modify(MUREKA_API_KEY: "test-key") do
      MusicGenerator::MurekaSoundtrackClient.call(
        file_id: "file_001", input_type: "video", prompt: "test"
      )
    end
    assert_requested(:post, SOUNDTRACK_URL,
                     headers: { "Authorization" => "Bearer test-key" })
  end

  test "sends Content-Type application/json header" do
    stub_success
    MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert_requested(:post, SOUNDTRACK_URL,
                     headers: { "Content-Type" => "application/json" })
  end

  test "request body uses video_id key for video input_type" do
    stub_success
    MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_video_001", input_type: "video", prompt: "test"
    )
    assert_requested(:post, SOUNDTRACK_URL) do |req|
      body = JSON.parse(req.body)
      body["video_id"] == "file_video_001" && !body.key?("image_id")
    end
  end

  test "request body uses image_id key for image input_type" do
    stub_success
    MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_img_001", input_type: "image", prompt: "test"
    )
    assert_requested(:post, SOUNDTRACK_URL) do |req|
      body = JSON.parse(req.body)
      body["image_id"] == "file_img_001" && !body.key?("video_id")
    end
  end

  test "request body includes prompt" do
    stub_success
    MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "energetic commercial"
    )
    assert_requested(:post, SOUNDTRACK_URL) do |req|
      body = JSON.parse(req.body)
      body["prompt"] == "energetic commercial"
    end
  end

  test "request body includes model auto" do
    stub_success
    MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert_requested(:post, SOUNDTRACK_URL) do |req|
      body = JSON.parse(req.body)
      body["model"] == "auto"
    end
  end

  test "request body includes n 2 by default" do
    stub_success
    MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert_requested(:post, SOUNDTRACK_URL) do |req|
      body = JSON.parse(req.body)
      body["n"] == 2
    end
  end

  # ---------------------------------------------------------------------------
  # Failure paths
  # ---------------------------------------------------------------------------

  test "returns failure :api_error on non-200 response" do
    stub_api_error
    result = MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert result.failure?
    assert_equal :api_error, result.errors
  end

  test "returns failure :timeout on network timeout" do
    stub_timeout
    result = MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert result.failure?
    assert_equal :timeout, result.errors
  end

  test "returns failure :missing_job_id when 200 response has no id field" do
    stub_success(body: JSON.generate({ "status" => "pending" }))
    result = MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert result.failure?
    assert_equal :missing_job_id, result.errors
  end

  test "returns failure :unexpected_error on SocketError" do
    stub_socket_error
    result = MusicGenerator::MurekaSoundtrackClient.call(
      file_id: "file_001", input_type: "video", prompt: "test"
    )
    assert result.failure?
    assert_equal :unexpected_error, result.errors
  end

  test "does not raise on any error path" do
    [ -> { stub_api_error }, -> { stub_timeout }, -> { stub_socket_error } ].each do |setup|
      setup.call
      assert_nothing_raised do
        MusicGenerator::MurekaSoundtrackClient.call(
          file_id: "file_001", input_type: "video", prompt: "test"
        )
      end
    end
  end
end
