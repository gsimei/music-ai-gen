# frozen_string_literal: true

require "test_helper"

# Stub the MusicGenerator namespace so the test file loads even before
# the implementation exists.  Tests will still fail with NameError on
# MusicGenerator::MurekaClient until the class is implemented.
module MusicGenerator; end unless defined?(MusicGenerator)

# Tests for MusicGenerator::MurekaClient
#
# Responsibilities:
# - POSTs to https://api.mureka.ai/v1/song/generate
# - Request body: { model: "auto", prompt:, lyrics: }, plus optional voice_id
# - Auth header: Authorization: Bearer <MUREKA_API_KEY>
# - Returns success? with value: { job_id: "..." } on HTTP 200 with id field
# - Returns failure?(:api_error) on non-200 HTTP response
# - Returns failure?(:timeout) on network timeout
# - Returns failure?(:missing_job_id) on 200 with no id in response body
# - Returns failure?(:unexpected_error) on SocketError (does not raise)
#
# Service interface:
#   MusicGenerator::MurekaClient.call(
#     prompt:   String,
#     lyrics:   String,
#     voice_id: String | nil
#   )
#
# Returns ServiceResult:
#   success? => true,  value: { job_id: String }
#   success? => false, errors: Symbol
class MusicGenerator::MurekaClientTest < ActiveSupport::TestCase
  MUREKA_SONG_URL = "https://api.mureka.ai/v1/song/generate"

  SUCCESS_BODY = JSON.generate({
    "id"     => "job_abc123",
    "status" => "pending"
  })

  test "gender uses the documented field and automatic choice omits it" do
    [ "female", "male", nil ].each do |gender|
      captured = nil
      stub_request(:post, MUREKA_SONG_URL).with { |request| captured = JSON.parse(request.body); true }
        .to_return(status: 200, body: SUCCESS_BODY)
      assert MusicGenerator::MurekaClient.call(prompt: "Brazilian pop", lyrics: "Oferta da semana", gender: gender).success?
      gender ? assert_equal(gender, captured["gender"]) : refute(captured.key?("gender"))
    end
  end

  test "invalid gender is rejected before a paid request" do
    result = MusicGenerator::MurekaClient.call(prompt: "Pop", lyrics: "Oferta", gender: "invalid")
    assert result.failure?
    assert_equal :invalid_gender, result.errors
    assert_not_requested :post, MUREKA_SONG_URL
  end

  def stub_mureka_success(body: SUCCESS_BODY)
    stub_request(:post, MUREKA_SONG_URL)
      .to_return(
        status:  200,
        headers: { "Content-Type" => "application/json" },
        body:    body
      )
  end

  def stub_mureka_api_error(status: 422)
    stub_request(:post, MUREKA_SONG_URL)
      .to_return(
        status:  status,
        headers: { "Content-Type" => "application/json" },
        body:    JSON.generate({ "error" => "Unprocessable entity" })
      )
  end

  def stub_mureka_timeout
    stub_request(:post, MUREKA_SONG_URL).to_timeout
  end

  def stub_mureka_socket_error
    stub_request(:post, MUREKA_SONG_URL).to_raise(SocketError)
  end

  # ---------------------------------------------------------------------------
  # Happy path — valid 200 response with job id
  # ---------------------------------------------------------------------------

  test "returns success when Mureka API responds 200 with job id" do
    stub_mureka_success

    result = MusicGenerator::MurekaClient.call(
      prompt:  "Upbeat pop song for a birthday",
      lyrics:  "Happy birthday dear Maria\nToday is your special day"
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "value contains job_id on success" do
    stub_mureka_success

    result = MusicGenerator::MurekaClient.call(
      prompt: "Upbeat pop song",
      lyrics: "Some lyrics here"
    )

    assert result.success?
    assert_equal "job_abc123", result.value[:job_id]
  end

  test "sends Authorization header with MUREKA_API_KEY" do
    stub_mureka_success

    ClimateControl.modify(MUREKA_API_KEY: "test-api-key-123") do
      MusicGenerator::MurekaClient.call(prompt: "Test prompt", lyrics: "Test lyrics")
    end

    assert_requested(:post, MUREKA_SONG_URL,
                     headers: { "Authorization" => "Bearer test-api-key-123" })
  end

  test "sends Content-Type application/json header" do
    stub_mureka_success

    MusicGenerator::MurekaClient.call(prompt: "Test prompt", lyrics: "Test lyrics")

    assert_requested(:post, MUREKA_SONG_URL,
                     headers: { "Content-Type" => "application/json" })
  end

  test "request body includes model auto, prompt, and lyrics" do
    stub_mureka_success

    MusicGenerator::MurekaClient.call(
      prompt: "A birthday pop song",
      lyrics: "Happy birthday to you"
    )

    assert_requested(:post, MUREKA_SONG_URL) do |req|
      body = JSON.parse(req.body)
      body["model"] == "auto" &&
        body["prompt"] == "A birthday pop song" &&
        body["lyrics"] == "Happy birthday to you"
    end
  end

  test "request body includes voice_id when provided" do
    stub_mureka_success

    MusicGenerator::MurekaClient.call(
      prompt:   "A birthday pop song",
      lyrics:   "Happy birthday to you",
      voice_id: "voice-001"
    )

    assert_requested(:post, MUREKA_SONG_URL) do |req|
      body = JSON.parse(req.body)
      body["voice_id"] == "voice-001"
    end
  end

  test "request body does not include voice_id when not provided" do
    stub_mureka_success

    MusicGenerator::MurekaClient.call(
      prompt: "A birthday pop song",
      lyrics: "Happy birthday to you"
    )

    assert_requested(:post, MUREKA_SONG_URL) do |req|
      body = JSON.parse(req.body)
      !body.key?("voice_id")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — non-200 HTTP response
  # ---------------------------------------------------------------------------

  test "returns failure on HTTP 422" do
    stub_mureka_api_error(status: 422)

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?, "Expected failure on HTTP 422"
  end

  test "error is :api_error on HTTP 422" do
    stub_mureka_api_error(status: 422)

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?
    assert_equal :api_error, result.errors
  end

  test "does not raise on HTTP 422" do
    stub_mureka_api_error(status: 422)

    assert_nothing_raised do
      MusicGenerator::MurekaClient.call(prompt: "Test prompt", lyrics: "Test lyrics")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — network timeout
  # ---------------------------------------------------------------------------

  test "returns failure on network timeout" do
    stub_mureka_timeout

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?, "Expected failure on timeout"
  end

  test "error is :timeout on network timeout" do
    stub_mureka_timeout

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?
    assert_equal :timeout, result.errors
  end

  test "does not raise on network timeout" do
    stub_mureka_timeout

    assert_nothing_raised do
      MusicGenerator::MurekaClient.call(prompt: "Test prompt", lyrics: "Test lyrics")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — 200 with no id field in response
  # ---------------------------------------------------------------------------

  test "returns failure when 200 response has no id field" do
    stub_mureka_success(body: JSON.generate({ "status" => "pending" }))

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?, "Expected failure when response has no id"
  end

  test "error is :missing_job_id when 200 response has no id field" do
    stub_mureka_success(body: JSON.generate({ "status" => "pending" }))

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?
    assert_equal :missing_job_id, result.errors
  end

  test "does not raise when 200 response has no id field" do
    stub_mureka_success(body: JSON.generate({ "status" => "pending" }))

    assert_nothing_raised do
      MusicGenerator::MurekaClient.call(prompt: "Test prompt", lyrics: "Test lyrics")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — SocketError (network-level error)
  # ---------------------------------------------------------------------------

  test "returns failure on SocketError" do
    stub_mureka_socket_error

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?, "Expected failure on SocketError"
  end

  test "error is :unexpected_error on SocketError" do
    stub_mureka_socket_error

    result = MusicGenerator::MurekaClient.call(
      prompt: "Test prompt",
      lyrics: "Test lyrics"
    )

    assert result.failure?
    assert_equal :unexpected_error, result.errors
  end

  test "does not raise on SocketError" do
    stub_mureka_socket_error

    assert_nothing_raised do
      MusicGenerator::MurekaClient.call(prompt: "Test prompt", lyrics: "Test lyrics")
    end
  end

  # ---------------------------------------------------------------------------
  # melody_hint — appended to prompt when provided
  # ---------------------------------------------------------------------------

  test "request body prompt includes melody_hint appended when provided" do
    stub_mureka_success
    hint = "More energetic, faster tempo, heavy drums"

    MusicGenerator::MurekaClient.call(
      prompt:      "A birthday pop song",
      lyrics:      "Happy birthday to you",
      melody_hint: hint
    )

    assert_requested(:post, MUREKA_SONG_URL) do |req|
      body = JSON.parse(req.body)
      body["prompt"].include?(hint)
    end
  end

  test "request body prompt is unchanged when melody_hint is nil" do
    stub_mureka_success
    original_prompt = "A birthday pop song"

    MusicGenerator::MurekaClient.call(
      prompt:      original_prompt,
      lyrics:      "Happy birthday to you",
      melody_hint: nil
    )

    assert_requested(:post, MUREKA_SONG_URL) do |req|
      body = JSON.parse(req.body)
      body["prompt"] == original_prompt
    end
  end

  test "request body prompt is unchanged when melody_hint is blank" do
    stub_mureka_success
    original_prompt = "A birthday pop song"

    MusicGenerator::MurekaClient.call(
      prompt:      original_prompt,
      lyrics:      "Happy birthday to you",
      melody_hint: ""
    )

    assert_requested(:post, MUREKA_SONG_URL) do |req|
      body = JSON.parse(req.body)
      body["prompt"] == original_prompt
    end
  end
end
