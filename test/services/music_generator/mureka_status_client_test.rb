# frozen_string_literal: true

require "test_helper"

# Stub the MusicGenerator namespace so the test file loads even before
# the implementation exists.  Tests will still fail with NameError on
# MusicGenerator::MurekaStatusClient until the class is implemented.
module MusicGenerator; end unless defined?(MusicGenerator)

# Tests for MusicGenerator::MurekaStatusClient
#
# Responsibilities:
# - GETs https://api.mureka.ai/v1/song/query/:job_id
# - Auth header: Authorization: Bearer <MUREKA_API_KEY>
# - status "pending": returns success? with { status: "pending", choices: nil }
# - status "succeeded": returns success? with { status: "succeeded", choices: [{url:, flac_url:, wav_url:, duration_ms:}, ...] }
# - status "failed": returns success? with { status: "failed", choices: nil }
# - HTTP 404 or other non-200: returns failure?(:api_error)
# - Net::ReadTimeout: returns failure?(:timeout)
# - Does not raise for any of the above
#
# Service interface:
#   MusicGenerator::MurekaStatusClient.call(job_id: String)
#
# Returns ServiceResult:
#   success? => true,  value: { status: String, choices: Array | nil }
#   success? => false, errors: Symbol
class MusicGenerator::MurekaStatusClientTest < ActiveSupport::TestCase
  JOB_ID = "job_abc123"
  MUREKA_STATUS_URL = "https://api.mureka.ai/v1/song/query/#{JOB_ID}"

  PENDING_BODY = JSON.generate({
    "id"     => JOB_ID,
    "status" => "pending"
  })

  SUCCEEDED_BODY = JSON.generate({
    "id"     => JOB_ID,
    "status" => "succeeded",
    "choices" => [
      {
        "url"      => "https://cdn.mureka.ai/song1.mp3",
        "flac_url" => "https://cdn.mureka.ai/song1.flac",
        "wav_url"  => "https://cdn.mureka.ai/song1.wav",
        "duration" => 180_000
      },
      {
        "url"      => "https://cdn.mureka.ai/song2.mp3",
        "flac_url" => "https://cdn.mureka.ai/song2.flac",
        "wav_url"  => "https://cdn.mureka.ai/song2.wav",
        "duration" => 192_000
      }
    ]
  })

  FAILED_BODY = JSON.generate({
    "id"     => JOB_ID,
    "status" => "failed"
  })

  def stub_status(body:, status: 200)
    stub_request(:get, MUREKA_STATUS_URL)
      .to_return(
        status:  status,
        headers: { "Content-Type" => "application/json" },
        body:    body
      )
  end

  def stub_status_timeout
    stub_request(:get, MUREKA_STATUS_URL)
      .to_raise(Net::ReadTimeout)
  end

  # ---------------------------------------------------------------------------
  # Status: pending
  # ---------------------------------------------------------------------------

  test "returns success when Mureka status is pending" do
    stub_status(body: PENDING_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?, "Expected success for pending status"
  end

  test "value[:status] is 'pending' when job is pending" do
    stub_status(body: PENDING_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    assert_equal "pending", result.value[:status]
  end

  test "value[:choices] is nil when job is pending" do
    stub_status(body: PENDING_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    assert_nil result.value[:choices]
  end

  # ---------------------------------------------------------------------------
  # Status: succeeded
  # ---------------------------------------------------------------------------

  test "returns success when Mureka status is succeeded" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?, "Expected success for succeeded status"
  end

  test "value[:status] is 'succeeded' when job has completed" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    assert_equal "succeeded", result.value[:status]
  end

  test "value[:choices] contains two entries when job succeeded" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    assert_equal 2, result.value[:choices].length
  end

  test "each choice has url mapped correctly" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    first = result.value[:choices].first
    assert_equal "https://cdn.mureka.ai/song1.mp3", first[:url]
  end

  test "each choice has flac_url mapped correctly" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    first = result.value[:choices].first
    assert_equal "https://cdn.mureka.ai/song1.flac", first[:flac_url]
  end

  test "each choice has wav_url mapped correctly" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    first = result.value[:choices].first
    assert_equal "https://cdn.mureka.ai/song1.wav", first[:wav_url]
  end

  test "each choice has duration_ms mapped from duration field" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    first  = result.value[:choices].first
    second = result.value[:choices].last
    assert_equal 180_000, first[:duration_ms]
    assert_equal 192_000, second[:duration_ms]
  end

  test "second choice url is mapped correctly" do
    stub_status(body: SUCCEEDED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    second = result.value[:choices].last
    assert_equal "https://cdn.mureka.ai/song2.mp3", second[:url]
  end

  # ---------------------------------------------------------------------------
  # Status: failed
  # ---------------------------------------------------------------------------

  test "returns success when Mureka status is failed" do
    stub_status(body: FAILED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?, "Expected success result even when Mureka reports failure"
  end

  test "value[:status] is 'failed' when Mureka reports failure" do
    stub_status(body: FAILED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    assert_equal "failed", result.value[:status]
  end

  test "value[:choices] is nil when Mureka reports failure" do
    stub_status(body: FAILED_BODY)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.success?
    assert_nil result.value[:choices]
  end

  # ---------------------------------------------------------------------------
  # Failure — HTTP 404
  # ---------------------------------------------------------------------------

  test "returns failure on HTTP 404" do
    stub_status(body: JSON.generate({ "error" => "Not found" }), status: 404)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.failure?, "Expected failure on HTTP 404"
  end

  test "error is :api_error on HTTP 404" do
    stub_status(body: JSON.generate({ "error" => "Not found" }), status: 404)

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.failure?
    assert_equal :api_error, result.errors
  end

  test "does not raise on HTTP 404" do
    stub_status(body: JSON.generate({ "error" => "Not found" }), status: 404)

    assert_nothing_raised do
      MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — Net::ReadTimeout
  # ---------------------------------------------------------------------------

  test "returns failure on Net::ReadTimeout" do
    stub_status_timeout

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.failure?, "Expected failure on Net::ReadTimeout"
  end

  test "error is :timeout on Net::ReadTimeout" do
    stub_status_timeout

    result = MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)

    assert result.failure?
    assert_equal :timeout, result.errors
  end

  test "does not raise on Net::ReadTimeout" do
    stub_status_timeout

    assert_nothing_raised do
      MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization header
  # ---------------------------------------------------------------------------

  test "sends Authorization header with MUREKA_API_KEY" do
    stub_status(body: PENDING_BODY)

    ClimateControl.modify(MUREKA_API_KEY: "test-api-key-456") do
      MusicGenerator::MurekaStatusClient.call(job_id: JOB_ID)
    end

    assert_requested(:get, MUREKA_STATUS_URL,
                     headers: { "Authorization" => "Bearer test-api-key-456" })
  end
end
