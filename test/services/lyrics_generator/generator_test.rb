# frozen_string_literal: true

require "test_helper"

# Tests for LyricsGenerator::Generator
#
# Responsibilities:
# - Orchestrates PromptBuilder → ClaudeClient → LyricsDraft + GenerationJob
# - mode :initial: creates LyricsDraft (version:1, source:"ai_generated", prompt_version:"v1.0")
#   and GenerationJob (status:"success")
# - mode :initial: returns failure if order has no briefing
# - mode :initial: returns failure (no LyricsDraft) if Claude fails; creates GenerationJob with status:"failed"
# - mode :regen: creates LyricsDraft (source:"regenerated", parent_draft_id set)
#   and increments order.lyrics_regen_used
# - mode :regen: returns failure with :regen_limit_reached when limit is exhausted
# - mode :regen: returns failure when parent_draft_id is invalid
#
# Service interface:
#   LyricsGenerator::Generator.call(
#     order:          Order instance,
#     mode:           :initial | :regen,
#     parent_draft_id: Integer | nil,   # required for :regen
#     user_feedback:  String | nil
#   )
#
# Returns ServiceResult:
#   success? => true,  value: LyricsDraft instance
#   success? => false, errors: Symbol | ActiveModel::Errors
class LyricsGenerator::GeneratorTest < ActiveSupport::TestCase
  VALID_LYRICS_JSON = JSON.generate({
    "title"    => "Buon Compleanno Mamma",
    "sections" => [
      { "type" => "verse",  "lines" => ["Buon compleanno cara mamma", "Ogni giorno sei la mia guida"] },
      { "type" => "chorus", "lines" => ["Ti voglio tanto bene", "Sei la mia luce"] }
    ]
  })

  def stub_claude_success
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status:  200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.generate({
          "id"      => "msg_01Test",
          "type"    => "message",
          "role"    => "assistant",
          "model"   => "claude-opus-4-7",
          "content" => [{ "type" => "text", "text" => VALID_LYRICS_JSON }],
          "stop_reason" => "end_turn",
          "usage" => { "input_tokens" => 200, "output_tokens" => 120 }
        })
      )
  end

  def stub_claude_failure
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status:  500,
        headers: { "Content-Type" => "application/json" },
        body:    JSON.generate({ "error" => { "message" => "Internal server error" } })
      )
  end

  # ---------------------------------------------------------------------------
  # mode :initial — happy path
  # ---------------------------------------------------------------------------

  test "mode :initial with valid briefing returns success" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(
      order: order,
      mode:  :initial
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "mode :initial creates exactly one LyricsDraft record" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    assert_difference "LyricsDraft.count", 1 do
      LyricsGenerator::Generator.call(order: order, mode: :initial)
    end
  end

  test "mode :initial draft has version 1" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.success?
    assert_equal 1, result.value.version
  end

  test "mode :initial draft has source ai_generated" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.success?
    assert_equal "ai_generated", result.value.source
  end

  test "mode :initial draft has prompt_version v1.0" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.success?
    assert_equal "v1.0", result.value.prompt_version
  end

  test "mode :initial draft is associated with the order" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.success?
    assert_equal order.id, result.value.order_id
  end

  test "mode :initial creates exactly one GenerationJob record" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    assert_difference "GenerationJob.count", 1 do
      LyricsGenerator::Generator.call(order: order, mode: :initial)
    end
  end

  test "mode :initial GenerationJob has status success" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    LyricsGenerator::Generator.call(order: order, mode: :initial)

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal "success", job.status
  end

  test "mode :initial GenerationJob is linked to the created LyricsDraft" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.success?
    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal result.value.id, job.lyrics_draft_id
  end

  test "mode :initial GenerationJob has provider anthropic" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    LyricsGenerator::Generator.call(order: order, mode: :initial)

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal "anthropic", job.provider
  end

  test "mode :initial GenerationJob has step lyrics_initial" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    LyricsGenerator::Generator.call(order: order, mode: :initial)

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal "lyrics_initial", job.step
  end

  test "mode :initial result value is a LyricsDraft instance" do
    stub_claude_success
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.success?
    assert_kind_of LyricsDraft, result.value
    assert result.value.persisted?
  end

  # ---------------------------------------------------------------------------
  # mode :initial — failure: no briefing
  # ---------------------------------------------------------------------------

  test "mode :initial without briefing returns failure" do
    order = orders(:b2c_lyrics_drafting)
    # Ensure this order has no briefing
    order.briefing&.destroy

    result = LyricsGenerator::Generator.call(
      order: order.reload,
      mode:  :initial
    )

    assert result.failure?, "Expected failure when order has no briefing"
  end

  test "mode :initial without briefing does not create LyricsDraft" do
    order = orders(:b2c_lyrics_drafting)
    order.briefing&.destroy

    assert_no_difference "LyricsDraft.count" do
      LyricsGenerator::Generator.call(order: order.reload, mode: :initial)
    end
  end

  test "mode :initial without briefing does not create GenerationJob" do
    order = orders(:b2c_lyrics_drafting)
    order.briefing&.destroy

    assert_no_difference "GenerationJob.count" do
      LyricsGenerator::Generator.call(order: order.reload, mode: :initial)
    end
  end

  # ---------------------------------------------------------------------------
  # mode :initial — failure: Claude API fails
  # ---------------------------------------------------------------------------

  test "mode :initial when Claude fails returns failure" do
    stub_claude_failure
    order = orders(:b2c_paid_with_stripe)

    result = LyricsGenerator::Generator.call(order: order, mode: :initial)

    assert result.failure?, "Expected failure when Claude API fails"
  end

  test "mode :initial when Claude fails does not create LyricsDraft" do
    stub_claude_failure
    order = orders(:b2c_paid_with_stripe)

    assert_no_difference "LyricsDraft.count" do
      LyricsGenerator::Generator.call(order: order, mode: :initial)
    end
  end

  test "mode :initial when Claude fails creates GenerationJob with status failed" do
    stub_claude_failure
    order = orders(:b2c_paid_with_stripe)

    assert_difference "GenerationJob.count", 1 do
      LyricsGenerator::Generator.call(order: order, mode: :initial)
    end

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal "failed", job.status
  end

  test "mode :initial when Claude fails GenerationJob has no lyrics_draft_id" do
    stub_claude_failure
    order = orders(:b2c_paid_with_stripe)

    LyricsGenerator::Generator.call(order: order, mode: :initial)

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_nil job.lyrics_draft_id
  end

  # ---------------------------------------------------------------------------
  # mode :regen — happy path
  # ---------------------------------------------------------------------------

  test "mode :regen with valid parent_draft returns success" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id,
      user_feedback:   "Piu romantica per favore"
    )

    assert result.success?, "Expected success but got: #{result.errors.inspect}"
  end

  test "mode :regen creates a new LyricsDraft" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    assert_difference "LyricsDraft.count", 1 do
      LyricsGenerator::Generator.call(
        order:           order,
        mode:            :regen,
        parent_draft_id: parent_draft.id
      )
    end
  end

  test "mode :regen draft has source regenerated" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    assert result.success?
    assert_equal "regenerated", result.value.source
  end

  test "mode :regen draft has parent_draft_id set" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    assert result.success?
    assert_equal parent_draft.id, result.value.parent_draft_id
  end

  test "mode :regen increments order.lyrics_regen_used by 1" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)
    before_count = order.lyrics_regen_used

    LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    assert_equal before_count + 1, order.reload.lyrics_regen_used
  end

  test "mode :regen creates a GenerationJob with status success" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    assert_difference "GenerationJob.count", 1 do
      LyricsGenerator::Generator.call(
        order:           order,
        mode:            :regen,
        parent_draft_id: parent_draft.id
      )
    end

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal "success", job.status
  end

  test "mode :regen GenerationJob has step lyrics_regen" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    job = GenerationJob.where(order: order).order(:created_at).last
    assert_equal "lyrics_regen", job.step
  end

  test "mode :regen draft has prompt_version v1.0" do
    stub_claude_success
    order        = orders(:b2c_lyrics_ready)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    assert result.success?
    assert_equal "v1.0", result.value.prompt_version
  end

  # ---------------------------------------------------------------------------
  # mode :regen — failure: regen limit reached
  # ---------------------------------------------------------------------------

  test "mode :regen returns failure with :regen_limit_reached when limit exhausted" do
    stub_claude_success
    order = orders(:b2c_lyrics_ready)
    # Exhaust the regen limit
    order.update_columns(lyrics_regen_used: order.lyrics_regen_limit)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    assert result.failure?, "Expected failure when regen limit is reached"
  end

  test "mode :regen with limit exhausted does not create LyricsDraft" do
    stub_claude_success
    order = orders(:b2c_lyrics_ready)
    order.update_columns(lyrics_regen_used: order.lyrics_regen_limit)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    assert_no_difference "LyricsDraft.count" do
      LyricsGenerator::Generator.call(
        order:           order,
        mode:            :regen,
        parent_draft_id: parent_draft.id
      )
    end
  end

  test "mode :regen limit reached error includes regen_limit_reached" do
    stub_claude_success
    order = orders(:b2c_lyrics_ready)
    order.update_columns(lyrics_regen_used: order.lyrics_regen_limit)
    parent_draft = lyrics_drafts(:draft_lyrics_ready_v1)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: parent_draft.id
    )

    assert result.failure?
    assert_includes result.errors.to_s, "regen_limit_reached"
  end

  # ---------------------------------------------------------------------------
  # mode :regen — failure: invalid parent_draft_id
  # ---------------------------------------------------------------------------

  test "mode :regen with nonexistent parent_draft_id returns failure" do
    stub_claude_success
    order = orders(:b2c_lyrics_ready)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: 9_999_999
    )

    assert result.failure?, "Expected failure for invalid parent_draft_id"
  end

  test "mode :regen with nil parent_draft_id returns failure" do
    stub_claude_success
    order = orders(:b2c_lyrics_ready)

    result = LyricsGenerator::Generator.call(
      order:           order,
      mode:            :regen,
      parent_draft_id: nil
    )

    assert result.failure?, "Expected failure when parent_draft_id is nil"
  end

  test "mode :regen with invalid parent_draft_id does not create LyricsDraft" do
    stub_claude_success
    order = orders(:b2c_lyrics_ready)

    assert_no_difference "LyricsDraft.count" do
      LyricsGenerator::Generator.call(
        order:           order,
        mode:            :regen,
        parent_draft_id: 9_999_999
      )
    end
  end
end
