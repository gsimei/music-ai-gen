# frozen_string_literal: true

require "test_helper"

# Tests for LyricsGenerator::ClaudeClient
#
# Responsibilities:
# - Posts a prompt to the Anthropic API (https://api.anthropic.com/v1/messages)
# - Parses the JSON content from response.content[0].text
# - Calculates input/output tokens and cost_usd from response.usage
# - Returns failure_result (not raises) when response text is not valid JSON
# - Returns failure_result when the API returns HTTP 500
# - Returns failure_result when the HTTP call times out
#
# Service interface:
#   LyricsGenerator::ClaudeClient.call(
#     system_prompt: String,
#     user_prompt:   String,
#     prompt_version: String
#   )
#
# Returns ServiceResult:
#   success? => true,  value: {
#     parsed_json:    Hash,
#     input_tokens:   Integer,
#     output_tokens:  Integer,
#     cost_usd:       Numeric,
#     raw_response:   String,
#     model:          String,
#     latency_ms:     Integer
#   }
#   success? => false, errors: Symbol | String
class LyricsGenerator::ClaudeClientTest < ActiveSupport::TestCase
  ANTHROPIC_MESSAGES_URL = "https://api.anthropic.com/v1/messages"

  VALID_LYRICS_JSON = JSON.generate({
    "title"    => "Buon Compleanno Mamma",
    "sections" => [
      { "type" => "verse",  "lines" => [ "Buon compleanno cara mamma", "Ogni giorno sei la mia guida" ] },
      { "type" => "chorus", "lines" => [ "Ti voglio tanto bene", "Sei la mia luce" ] }
    ]
  })

  # ---------------------------------------------------------------------------
  # Helpers — build a fake Anthropic response body
  # ---------------------------------------------------------------------------

  def anthropic_response_body(text:, input_tokens: 150, output_tokens: 80)
    JSON.generate({
      "id"      => "msg_01Abc123",
      "type"    => "message",
      "role"    => "assistant",
      "model"   => "claude-opus-4-7",
      "content" => [
        { "type" => "text", "text" => text }
      ],
      "stop_reason" => "end_turn",
      "usage" => {
        "input_tokens"  => input_tokens,
        "output_tokens" => output_tokens
      }
    })
  end

  def stub_anthropic_success(text: VALID_LYRICS_JSON, input_tokens: 150, output_tokens: 80)
    stub_request(:post, ANTHROPIC_MESSAGES_URL)
      .to_return(
        status:  200,
        headers: { "Content-Type" => "application/json" },
        body:    anthropic_response_body(text: text, input_tokens: input_tokens, output_tokens: output_tokens)
      )
  end

  def stub_anthropic_server_error
    stub_request(:post, ANTHROPIC_MESSAGES_URL)
      .to_return(
        status:  500,
        headers: { "Content-Type" => "application/json" },
        body:    JSON.generate({ "error" => { "type" => "api_error", "message" => "Internal server error" } })
      )
  end

  def stub_anthropic_timeout
    stub_request(:post, ANTHROPIC_MESSAGES_URL)
      .to_timeout
  end

  # ---------------------------------------------------------------------------
  # Happy path — valid JSON response
  # ---------------------------------------------------------------------------

  test "returns success when Anthropic API responds with valid JSON lyrics" do
    stub_anthropic_success

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song for Maria.",
      prompt_version: "v1.0"
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "parsed_json is a Hash on success" do
    stub_anthropic_success

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert_kind_of Hash, result.value[:parsed_json]
  end

  test "parsed_json contains expected keys from Claude response" do
    stub_anthropic_success

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert result.value[:parsed_json].key?("title")
    assert result.value[:parsed_json].key?("sections")
  end

  test "input_tokens is populated from API usage" do
    stub_anthropic_success(input_tokens: 150, output_tokens: 80)

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert_equal 150, result.value[:input_tokens]
  end

  test "output_tokens is populated from API usage" do
    stub_anthropic_success(input_tokens: 150, output_tokens: 80)

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert_equal 80, result.value[:output_tokens]
  end

  test "cost_usd is calculated and is a positive numeric" do
    stub_anthropic_success(input_tokens: 150, output_tokens: 80)

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert_kind_of Numeric, result.value[:cost_usd]
    assert result.value[:cost_usd] > 0, "cost_usd should be positive"
  end

  test "model name is present in result value" do
    stub_anthropic_success

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert_kind_of String, result.value[:model]
    assert_not result.value[:model].empty?
  end

  test "latency_ms is a non-negative integer" do
    stub_anthropic_success

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert_kind_of Integer, result.value[:latency_ms]
    assert result.value[:latency_ms] >= 0
  end

  test "raw_response is present in result value" do
    stub_anthropic_success

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.success?
    assert result.value.key?(:raw_response)
  end

  # ---------------------------------------------------------------------------
  # Failure — Claude responds with non-JSON text
  # ---------------------------------------------------------------------------

  test "returns failure when Claude response text is not valid JSON" do
    stub_anthropic_success(text: "Desculpe, nao consigo gerar letras agora.")

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.failure?, "Expected failure when response is not JSON"
  end

  test "does not raise exception when Claude responds with non-JSON text" do
    stub_anthropic_success(text: "This is not JSON at all!")

    # Must NOT raise — should return failure_result instead
    assert_nothing_raised do
      LyricsGenerator::ClaudeClient.call(
        system_prompt:  "You are a music lyrics generator.",
        user_prompt:    "Write a birthday song.",
        prompt_version: "v1.0"
      )
    end
  end

  test "failure result error communicates invalid JSON cause" do
    stub_anthropic_success(text: "Not JSON")

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.failure?
    assert_not_nil result.errors
  end

  # ---------------------------------------------------------------------------
  # Failure — API returns HTTP 500
  # ---------------------------------------------------------------------------

  test "returns failure when Anthropic API returns HTTP 500" do
    stub_anthropic_server_error

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.failure?, "Expected failure on HTTP 500"
  end

  test "does not raise when Anthropic API returns HTTP 500" do
    stub_anthropic_server_error

    assert_nothing_raised do
      LyricsGenerator::ClaudeClient.call(
        system_prompt:  "You are a music lyrics generator.",
        user_prompt:    "Write a birthday song.",
        prompt_version: "v1.0"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — network timeout
  # ---------------------------------------------------------------------------

  test "returns failure when HTTP call times out" do
    stub_anthropic_timeout

    result = LyricsGenerator::ClaudeClient.call(
      system_prompt:  "You are a music lyrics generator.",
      user_prompt:    "Write a birthday song.",
      prompt_version: "v1.0"
    )

    assert result.failure?, "Expected failure on timeout"
  end

  test "does not raise when HTTP call times out" do
    stub_anthropic_timeout

    assert_nothing_raised do
      LyricsGenerator::ClaudeClient.call(
        system_prompt:  "You are a music lyrics generator.",
        user_prompt:    "Write a birthday song.",
        prompt_version: "v1.0"
      )
    end
  end
end
