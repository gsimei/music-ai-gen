require "test_helper"

class MusicGenerationTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "STATUSES constant contains expected values" do
    assert_equal %w[pending processing completed failed cancelled], MusicGeneration::STATUSES
  end

  test "PROVIDERS constant contains expected values" do
    assert_equal %w[mureka], MusicGeneration::PROVIDERS
  end

  # ---------------------------------------------------------------------------
  # Validations — iteration
  # ---------------------------------------------------------------------------
  test "is invalid without iteration" do
    gen = music_generations(:generation_pending)
    gen.iteration = nil
    assert_not gen.valid?
    assert gen.errors[:iteration].any?
  end

  test "is invalid with iteration zero" do
    gen = music_generations(:generation_pending)
    gen.iteration = 0
    assert_not gen.valid?
    assert gen.errors[:iteration].any?
  end

  test "is invalid with non-integer iteration" do
    gen = music_generations(:generation_pending)
    gen.iteration = 1.5
    assert_not gen.valid?
    assert gen.errors[:iteration].any?
  end

  test "is invalid with duplicate iteration for same order" do
    # generation_pending is already iteration 1 for b2c_paid
    gen = MusicGeneration.new(
      order: orders(:b2c_paid),
      voice: voices(:standard_voice),
      lyrics_draft: lyrics_drafts(:draft_v1),
      iteration: 1,
      provider: "mureka",
      music_style: "pop"
    )
    assert_not gen.valid?
    assert gen.errors[:iteration].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — provider
  # ---------------------------------------------------------------------------
  test "is invalid without provider" do
    gen = music_generations(:generation_pending)
    gen.provider = nil
    assert_not gen.valid?
    assert gen.errors[:provider].any?
  end

  test "is invalid with unrecognized provider" do
    gen = music_generations(:generation_pending)
    gen.provider = "soundcloud"
    assert_not gen.valid?
    assert gen.errors[:provider].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — music_style
  # ---------------------------------------------------------------------------
  test "is invalid without music_style" do
    gen = music_generations(:generation_pending)
    gen.music_style = nil
    assert_not gen.valid?
    assert gen.errors[:music_style].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — Statusable (status inclusion)
  # ---------------------------------------------------------------------------
  test "is invalid with unrecognized status" do
    gen = music_generations(:generation_pending)
    gen.status = "flying"
    assert_not gen.valid?
    assert gen.errors[:status].any?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs_to order" do
    reflection = MusicGeneration.reflect_on_association(:order)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to voice" do
    reflection = MusicGeneration.reflect_on_association(:voice)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to lyrics_draft" do
    reflection = MusicGeneration.reflect_on_association(:lyrics_draft)
    assert_not_nil reflection
    assert_equal :belongs_to, reflection.macro
  end

  test "belongs_to parent_generation optional with class_name MusicGeneration" do
    reflection = MusicGeneration.reflect_on_association(:parent_generation)
    assert_not_nil reflection
    assert_equal "MusicGeneration", reflection.options[:class_name]
    assert reflection.options[:optional]
  end

  test "has_many child_generations with class_name MusicGeneration and dependent nullify" do
    reflection = MusicGeneration.reflect_on_association(:child_generations)
    assert_not_nil reflection
    assert_equal "MusicGeneration", reflection.options[:class_name]
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "has_many order_assets with dependent destroy" do
    reflection = MusicGeneration.reflect_on_association(:order_assets)
    assert_not_nil reflection
    assert_equal :destroy, reflection.options[:dependent]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "completed scope returns only completed generations" do
    result = MusicGeneration.completed
    assert result.any?
    assert result.all? { |g| g.status == "completed" }
  end

  test "pending scope returns only pending generations" do
    result = MusicGeneration.pending
    assert result.any?
    assert result.all? { |g| g.status == "pending" }
  end

  test "failed scope returns no records when none are failed" do
    result = MusicGeneration.failed
    # Verify it returns an ActiveRecord::Relation (even if empty)
    assert_respond_to result, :count
  end

  # ---------------------------------------------------------------------------
  # Predicates — status
  # ---------------------------------------------------------------------------
  %w[pending processing completed failed cancelled].each do |status|
    test "#{status}? returns true when status is #{status}" do
      gen = music_generations(:generation_pending)
      gen.status = status
      assert gen.public_send(:"#{status}?")
    end
  end

  # ---------------------------------------------------------------------------
  # Predicates — variant completion
  # ---------------------------------------------------------------------------
  test "variant_a_complete? returns true when variant_a_full_url is present" do
    gen = music_generations(:generation_completed)
    assert gen.variant_a_complete?
  end

  test "variant_a_complete? returns false when variant_a_full_url is blank" do
    gen = music_generations(:generation_pending)
    gen.variant_a_full_url = nil
    assert_not gen.variant_a_complete?
  end

  test "variant_b_complete? returns true when variant_b_full_url is present" do
    gen = music_generations(:generation_completed)
    assert gen.variant_b_complete?
  end

  test "variant_b_complete? returns false when variant_b_full_url is blank" do
    gen = music_generations(:generation_pending)
    gen.variant_b_full_url = nil
    assert_not gen.variant_b_complete?
  end

  test "both_variants_complete? returns true when both urls are present" do
    gen = music_generations(:generation_completed)
    assert gen.both_variants_complete?
  end

  test "both_variants_complete? returns false when variant_a is missing" do
    gen = music_generations(:generation_completed)
    gen.variant_a_full_url = nil
    assert_not gen.both_variants_complete?
  end

  test "both_variants_complete? returns false when variant_b is missing" do
    gen = music_generations(:generation_completed)
    gen.variant_b_full_url = nil
    assert_not gen.both_variants_complete?
  end

  # ---------------------------------------------------------------------------
  # Methods
  # ---------------------------------------------------------------------------
  test "selected_variant_url returns variant_a_full_url for variant 'a'" do
    gen = music_generations(:generation_completed)
    assert_equal gen.variant_a_full_url, gen.selected_variant_url("a")
  end

  test "selected_variant_url returns variant_b_full_url for variant 'b'" do
    gen = music_generations(:generation_completed)
    assert_equal gen.variant_b_full_url, gen.selected_variant_url("b")
  end

  test "selected_variant_url returns nil for unknown variant" do
    gen = music_generations(:generation_completed)
    assert_nil gen.selected_variant_url("c")
  end
end
