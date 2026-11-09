# frozen_string_literal: true

require "test_helper"

module MusicGenerator; end unless defined?(MusicGenerator)

class MusicGenerator::MurekaSoundtrackStatusClientTest < ActiveSupport::TestCase
  BASE_URL = "https://api.mureka.ai/v1/soundtrack/query"
  JOB_ID   = "job_st_status_test"
  URL      = "#{BASE_URL}/#{JOB_ID}"

  SUCCEEDED_BODY = JSON.generate({
    "status"  => "succeeded",
    "choices" => [
      { "url" => "https://cdn.mureka.ai/st1.mp4", "duration" => 30_000 },
      { "url" => "https://cdn.mureka.ai/st2.mp4", "duration" => 32_000 }
    ]
  })

  def stub_success(body: SUCCEEDED_BODY)
    stub_request(:get, URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: body)
  end

  def stub_api_error
    stub_request(:get, URL).to_return(status: 500, body: "error")
  end

  def stub_timeout
    stub_request(:get, URL).to_timeout
  end

  def stub_socket_error
    stub_request(:get, URL).to_raise(SocketError)
  end

  def call_client
    MusicGenerator::MurekaSoundtrackStatusClient.call(job_id: JOB_ID)
  end

  # ---------------------------------------------------------------------------
  # Happy path — succeeded
  # ---------------------------------------------------------------------------

  test "returns success result on HTTP 200" do
    stub_success
    assert call_client.success?
  end

  test "status is succeeded when Mureka reports succeeded" do
    stub_success
    assert_equal "succeeded", call_client.value[:status]
  end

  test "choices are mapped with url and duration_ms" do
    stub_success
    choices = call_client.value[:choices]
    assert_equal "https://cdn.mureka.ai/st1.mp4", choices.first[:url]
    assert_equal 30_000, choices.first[:duration_ms]
  end

  test "choices do not include lyrics_sections" do
    stub_success
    choice = call_client.value[:choices].first
    assert_not choice.key?(:lyrics_sections)
  end

  test "sends Authorization header" do
    stub_success
    ClimateControl.modify(MUREKA_API_KEY: "test-key") do
      MusicGenerator::MurekaSoundtrackStatusClient.call(job_id: JOB_ID)
    end
    assert_requested(:get, URL, headers: { "Authorization" => "Bearer test-key" })
  end

  # ---------------------------------------------------------------------------
  # Status: pending
  # ---------------------------------------------------------------------------

  test "returns pending status when Mureka reports running" do
    stub_success(body: JSON.generate({ "status" => "running" }))
    result = call_client
    assert result.success?
    assert_equal "pending", result.value[:status]
    assert_nil result.value[:choices]
  end

  # ---------------------------------------------------------------------------
  # Status: failed
  # ---------------------------------------------------------------------------

  test "returns failed status when Mureka reports failed" do
    stub_success(body: JSON.generate({ "status" => "failed" }))
    result = call_client
    assert result.success?
    assert_equal "failed", result.value[:status]
  end

  test "returns failed status when Mureka reports timeouted" do
    stub_success(body: JSON.generate({ "status" => "timeouted" }))
    result = call_client
    assert_equal "failed", result.value[:status]
  end

  # ---------------------------------------------------------------------------
  # Failure paths
  # ---------------------------------------------------------------------------

  test "returns failure :api_error on non-200 response" do
    stub_api_error
    assert_equal :api_error, call_client.errors
  end

  test "returns failure :timeout on network timeout" do
    stub_timeout
    assert_equal :timeout, call_client.errors
  end

  test "returns failure :unexpected_error on SocketError" do
    stub_socket_error
    assert_equal :unexpected_error, call_client.errors
  end

  test "does not raise on any error path" do
    [ -> { stub_api_error }, -> { stub_timeout }, -> { stub_socket_error } ].each do |setup|
      setup.call
      assert_nothing_raised { call_client }
    end
  end
end
