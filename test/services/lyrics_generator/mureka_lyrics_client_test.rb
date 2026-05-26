# frozen_string_literal: true

require "test_helper"

# Tests for LyricsGenerator::MurekaLyricsClient
#
# Responsibilities:
# - POSTs { "prompt": "..." } to https://api.mureka.ai/v1/lyrics/generate
# - Returns success? with value: { title:, lyrics:, raw_response:, latency_ms: }
# - Returns failure? (does not raise) on HTTP 500
# - Returns failure? (does not raise) on network timeout
# - Returns failure? when "title" is blank in response
# - Returns failure? when "lyrics" is blank in response
# - Returns failure? (does not raise) when response body is not valid JSON
#
# Service interface:
#   LyricsGenerator::MurekaLyricsClient.call(prompt: String)
#
# Returns ServiceResult:
#   success? => true,  value: {
#     title:        String   (non-empty),
#     lyrics:       String   (non-empty),
#     raw_response: String,
#     latency_ms:   Integer  (>= 0)
#   }
#   success? => false, errors: Symbol | String
class LyricsGenerator::MurekaLyricsClientTest < ActiveSupport::TestCase
  MUREKA_LYRICS_URL = "https://api.mureka.ai/v1/lyrics/generate"

  VALID_MUREKA_RESPONSE = JSON.generate({
    "title"  => "Buon Compleanno Mamma",
    "lyrics" => "Buon compleanno cara mamma\nOgni giorno sei la mia guida\nTi voglio tanto bene\nSei la mia luce"
  })

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def stub_mureka_success(body: VALID_MUREKA_RESPONSE)
    stub_request(:post, MUREKA_LYRICS_URL)
      .to_return(
        status:  200,
        headers: { "Content-Type" => "application/json" },
        body:    body
      )
  end

  def stub_mureka_server_error
    stub_request(:post, MUREKA_LYRICS_URL)
      .to_return(
        status:  500,
        headers: { "Content-Type" => "application/json" },
        body:    JSON.generate({ "error" => "Internal server error" })
      )
  end

  def stub_mureka_timeout
    stub_request(:post, MUREKA_LYRICS_URL)
      .to_timeout
  end

  # ---------------------------------------------------------------------------
  # Happy path — valid 200 response
  # ---------------------------------------------------------------------------

  test "returns success when Mureka API responds with valid title and lyrics" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "value[:title] is a non-empty String on success" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?
    assert_kind_of String, result.value[:title]
    assert_not result.value[:title].empty?, "Expected title to be non-empty"
  end

  test "value[:lyrics] is a non-empty String on success" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?
    assert_kind_of String, result.value[:lyrics]
    assert_not result.value[:lyrics].empty?, "Expected lyrics to be non-empty"
  end

  test "value[:raw_response] is present on success" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?
    assert result.value.key?(:raw_response), "Expected raw_response key to be present"
    assert_not result.value[:raw_response].blank?
  end

  test "value[:latency_ms] is a non-negative Integer on success" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?
    assert_kind_of Integer, result.value[:latency_ms]
    assert result.value[:latency_ms] >= 0, "Expected latency_ms to be non-negative"
  end

  test "value[:title] matches the title from the API response" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?
    assert_equal "Buon Compleanno Mamma", result.value[:title]
  end

  test "value[:lyrics] matches the lyrics from the API response" do
    stub_mureka_success

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song for Maria.")

    assert result.success?
    assert_includes result.value[:lyrics], "Buon compleanno cara mamma"
  end

  # ---------------------------------------------------------------------------
  # Failure — HTTP 500
  # ---------------------------------------------------------------------------

  test "returns failure when Mureka API returns HTTP 500" do
    stub_mureka_server_error

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure on HTTP 500"
  end

  test "does not raise when Mureka API returns HTTP 500" do
    stub_mureka_server_error

    assert_nothing_raised do
      LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — network timeout
  # ---------------------------------------------------------------------------

  test "returns failure when HTTP call times out" do
    stub_mureka_timeout

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure on timeout"
  end

  test "does not raise when HTTP call times out" do
    stub_mureka_timeout

    assert_nothing_raised do
      LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — blank title in response
  # ---------------------------------------------------------------------------

  test "returns failure when title is blank in response" do
    stub_mureka_success(body: JSON.generate({ "title" => "", "lyrics" => "Some lyrics here" }))

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure when title is blank"
  end

  test "does not raise when title is blank in response" do
    stub_mureka_success(body: JSON.generate({ "title" => "", "lyrics" => "Some lyrics here" }))

    assert_nothing_raised do
      LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")
    end
  end

  test "returns failure when title key is missing from response" do
    stub_mureka_success(body: JSON.generate({ "lyrics" => "Some lyrics here" }))

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure when title key is absent"
  end

  # ---------------------------------------------------------------------------
  # Failure — blank lyrics in response
  # ---------------------------------------------------------------------------

  test "returns failure when lyrics is blank in response" do
    stub_mureka_success(body: JSON.generate({ "title" => "Some Title", "lyrics" => "" }))

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure when lyrics is blank"
  end

  test "does not raise when lyrics is blank in response" do
    stub_mureka_success(body: JSON.generate({ "title" => "Some Title", "lyrics" => "" }))

    assert_nothing_raised do
      LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")
    end
  end

  test "returns failure when lyrics key is missing from response" do
    stub_mureka_success(body: JSON.generate({ "title" => "Some Title" }))

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure when lyrics key is absent"
  end

  # ---------------------------------------------------------------------------
  # Failure — response body is not valid JSON
  # ---------------------------------------------------------------------------

  test "returns failure when response body is not valid JSON" do
    stub_mureka_success(body: "This is not JSON at all!")

    result = LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")

    assert result.failure?, "Expected failure when response body is not valid JSON"
  end

  test "does not raise when response body is not valid JSON" do
    stub_mureka_success(body: "This is not JSON at all!")

    assert_nothing_raised do
      LyricsGenerator::MurekaLyricsClient.call(prompt: "Write a birthday song.")
    end
  end
end
