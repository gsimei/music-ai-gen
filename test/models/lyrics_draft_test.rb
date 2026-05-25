require "test_helper"

class LyricsDraftTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "SOURCES constant contains expected values" do
    assert_equal %w[ai_generated user_edited regenerated], LyricsDraft::SOURCES
  end

  # ---------------------------------------------------------------------------
  # Validations — version
  # ---------------------------------------------------------------------------
  test "is invalid without version" do
    draft = lyrics_drafts(:draft_v1)
    draft.version = nil
    assert_not draft.valid?
    assert draft.errors[:version].any?
  end

  test "is invalid with version zero" do
    draft = lyrics_drafts(:draft_v1)
    draft.version = 0
    assert_not draft.valid?
    assert draft.errors[:version].any?
  end

  test "is invalid with non-integer version" do
    draft = lyrics_drafts(:draft_v1)
    draft.version = 1.5
    assert_not draft.valid?
    assert draft.errors[:version].any?
  end

  test "is invalid with duplicate version for same order" do
    # draft_v1 is already version 1 for b2c_paid
    draft = LyricsDraft.new(
      order: orders(:b2c_paid),
      version: 1,
      source: "user_edited",
      content: "Some content"
    )
    assert_not draft.valid?
    assert draft.errors[:version].any?
  end

  test "is valid with same version for different orders" do
    draft = LyricsDraft.new(
      order: orders(:b2c_pending),
      version: 1,
      source: "ai_generated",
      content: "Some content"
    )
    draft.validate
    assert_empty draft.errors[:version]
  end

  # ---------------------------------------------------------------------------
  # Validations — source
  # ---------------------------------------------------------------------------
  test "is invalid without source" do
    draft = lyrics_drafts(:draft_v1)
    draft.source = nil
    assert_not draft.valid?
    assert draft.errors[:source].any?
  end

  test "is invalid with unrecognized source" do
    draft = lyrics_drafts(:draft_v1)
    draft.source = "unknown"
    assert_not draft.valid?
    assert draft.errors[:source].any?
  end

  test "is valid with each known source" do
    %w[ai_generated user_edited regenerated].each do |source|
      draft = lyrics_drafts(:draft_v1)
      draft.source = source
      # regenerated requires parent_draft_id, so skip that validation check here
      draft.validate
      assert_empty draft.errors[:source], "Expected source '#{source}' to be valid"
    end
  end

  # ---------------------------------------------------------------------------
  # Validations — content
  # ---------------------------------------------------------------------------
  test "is invalid without content" do
    draft = lyrics_drafts(:draft_v1)
    draft.content = nil
    assert_not draft.valid?
    assert draft.errors[:content].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — custom: parent_required_when_regenerated
  # ---------------------------------------------------------------------------
  test "is invalid when source is regenerated but parent_draft_id is absent" do
    draft = LyricsDraft.new(
      order: orders(:b2c_paid),
      version: 3,
      source: "regenerated",
      content: "New regenerated content",
      parent_draft: nil
    )
    assert_not draft.valid?
    assert draft.errors[:parent_draft_id].any?
  end

  test "is valid when source is regenerated and parent_draft_id is present" do
    draft = lyrics_drafts(:draft_v2_regen)
    assert draft.valid?
  end

  test "does not require parent_draft when source is ai_generated" do
    draft = lyrics_drafts(:draft_v1)
    draft.parent_draft = nil
    draft.validate
    assert_empty draft.errors[:parent_draft_id]
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order" do
    reflection = LyricsDraft.reflect_on_association(:order)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to parent_draft optional with class_name LyricsDraft" do
    reflection = LyricsDraft.reflect_on_association(:parent_draft)
    assert_not_nil reflection
    assert_equal "LyricsDraft", reflection.options[:class_name]
    assert reflection.options[:optional]
  end

  test "has_many child_drafts with class_name LyricsDraft and dependent nullify" do
    reflection = LyricsDraft.reflect_on_association(:child_drafts)
    assert_not_nil reflection
    assert_equal "LyricsDraft", reflection.options[:class_name]
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "has_many music_generations with dependent restrict_with_error" do
    reflection = LyricsDraft.reflect_on_association(:music_generations)
    assert_not_nil reflection
    assert_equal :restrict_with_error, reflection.options[:dependent]
  end

  test "has_many generation_jobs with dependent nullify" do
    reflection = LyricsDraft.reflect_on_association(:generation_jobs)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "approved scope returns only approved drafts" do
    result = LyricsDraft.approved
    assert result.any?
    assert result.all?(&:is_approved)
  end

  test "locked scope returns only locked drafts" do
    result = LyricsDraft.locked
    assert result.any?
    assert result.all?(&:is_locked)
  end

  test "latest_for returns the draft with highest version for given order_id" do
    order = orders(:b2c_paid)
    result = LyricsDraft.latest_for(order.id)
    assert_not_nil result
    assert_equal 2, result.version  # draft_v2_regen has version 2
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "approved? returns true when is_approved is true" do
    draft = lyrics_drafts(:draft_approved)
    assert draft.approved?
  end

  test "approved? returns false when is_approved is false" do
    draft = lyrics_drafts(:draft_v1)
    assert_not draft.approved?
  end

  test "locked? returns true when is_locked is true" do
    draft = lyrics_drafts(:draft_approved)
    assert draft.locked?
  end

  test "locked? returns false when is_locked is false" do
    draft = lyrics_drafts(:draft_v1)
    assert_not draft.locked?
  end

  test "regenerated? returns true when source is regenerated" do
    draft = lyrics_drafts(:draft_v2_regen)
    assert draft.regenerated?
  end

  test "regenerated? returns false when source is ai_generated" do
    draft = lyrics_drafts(:draft_v1)
    assert_not draft.regenerated?
  end

  test "ai_generated? returns true when source is ai_generated" do
    draft = lyrics_drafts(:draft_v1)
    assert draft.ai_generated?
  end

  test "ai_generated? returns false when source is regenerated" do
    draft = lyrics_drafts(:draft_v2_regen)
    assert_not draft.ai_generated?
  end
end
