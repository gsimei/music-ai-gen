require "test_helper"

class VoiceTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------
  test "PROVIDERS constant contains expected values" do
    assert_equal %w[mureka], Voice::PROVIDERS
  end

  test "GENDERS constant contains expected values" do
    assert_equal %w[male female neutral], Voice::GENDERS
  end

  test "VALID_BRANDS constant contains expected values" do
    assert_equal %w[b2b b2c], Voice::VALID_BRANDS
  end

  test "MIN_TIER_RANGE constant is 0..1" do
    assert_equal (0..1), Voice::MIN_TIER_RANGE
  end

  # ---------------------------------------------------------------------------
  # Validations — provider
  # ---------------------------------------------------------------------------
  test "is invalid without provider" do
    voice = voices(:standard_voice)
    voice.provider = nil
    assert_not voice.valid?
    assert voice.errors[:provider].any?
  end

  test "is invalid with unknown provider" do
    voice = voices(:standard_voice)
    voice.provider = "soundcloud"
    assert_not voice.valid?
    assert voice.errors[:provider].any?
  end

  test "is valid with provider mureka" do
    voice = voices(:standard_voice)
    assert voice.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — name
  # ---------------------------------------------------------------------------
  test "is invalid without name" do
    voice = voices(:standard_voice)
    voice.name = nil
    assert_not voice.valid?
    assert voice.errors[:name].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — slug
  # ---------------------------------------------------------------------------
  test "is invalid without slug" do
    voice = voices(:standard_voice)
    voice.slug = nil
    assert_not voice.valid?
    assert voice.errors[:slug].any?
  end

  test "is invalid with duplicate slug" do
    voice = Voice.new(
      provider: "mureka",
      external_id: "voice-999",
      name: "Duplicate",
      slug: "sofia",  # already taken by standard_voice
      min_tier: 0,
      allowed_brands: %w[b2b b2c]
    )
    assert_not voice.valid?
    assert voice.errors[:slug].any?
  end

  test "is invalid with slug not matching kebab format" do
    voice = voices(:standard_voice)
    voice.slug = "My Voice!!!"
    assert_not voice.valid?
    assert voice.errors[:slug].any?
  end

  test "is valid with properly formatted slug" do
    voice = voices(:standard_voice)
    voice.slug = "my-voice-01"
    assert voice.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — gender
  # ---------------------------------------------------------------------------
  test "is valid with nil gender (allow_nil)" do
    voice = voices(:standard_voice)
    voice.gender = nil
    voice.validate
    assert_empty voice.errors[:gender]
  end

  test "is invalid with unrecognized gender" do
    voice = voices(:standard_voice)
    voice.gender = "other"
    assert_not voice.valid?
    assert voice.errors[:gender].any?
  end

  # ---------------------------------------------------------------------------
  # Validations — min_tier
  # ---------------------------------------------------------------------------
  test "is invalid with min_tier outside 0..1 range" do
    voice = voices(:standard_voice)
    voice.min_tier = 5
    assert_not voice.valid?
    assert voice.errors[:min_tier].any?
  end

  test "is valid with min_tier 0" do
    voice = voices(:standard_voice)
    voice.min_tier = 0
    assert voice.valid?
  end

  test "is valid with min_tier 1" do
    voice = voices(:pro_voice)
    assert voice.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — allowed_brands (custom: subset of VALID_BRANDS)
  # ---------------------------------------------------------------------------
  test "is invalid when allowed_brands contains unknown brand" do
    voice = voices(:standard_voice)
    voice.allowed_brands = %w[b2b b3x]
    assert_not voice.valid?
    assert voice.errors[:allowed_brands].any?
  end

  test "is valid with allowed_brands subset of VALID_BRANDS" do
    voice = voices(:b2b_only_voice)
    assert voice.valid?
  end

  # ---------------------------------------------------------------------------
  # Validations — external_id OR mureka_prompt (custom)
  # ---------------------------------------------------------------------------
  test "is invalid when both external_id and mureka_prompt are blank" do
    voice = voices(:standard_voice)
    voice.external_id = nil
    voice.mureka_prompt = nil
    assert_not voice.valid?
    assert voice.errors[:base].any?
  end

  test "is valid with only external_id present" do
    voice = voices(:standard_voice)
    voice.mureka_prompt = nil
    assert voice.valid?
  end

  test "is valid with only mureka_prompt present" do
    voice = voices(:pro_voice)
    voice.external_id = nil
    assert voice.valid?
  end

  test "is valid with both external_id and mureka_prompt present" do
    voice = voices(:standard_voice)
    voice.mureka_prompt = "warm, emotional"
    assert voice.valid?
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "responds to briefings association" do
    voice = voices(:standard_voice)
    assert_respond_to voice, :briefings
  end

  test "briefings association has dependent nullify" do
    reflection = Voice.reflect_on_association(:briefings)
    assert_not_nil reflection
    assert_equal :nullify, reflection.options[:dependent]
  end

  test "responds to music_generations association" do
    voice = voices(:standard_voice)
    assert_respond_to voice, :music_generations
  end

  test "music_generations association has dependent restrict_with_error" do
    reflection = Voice.reflect_on_association(:music_generations)
    assert_not_nil reflection
    assert_equal :restrict_with_error, reflection.options[:dependent]
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test "active scope returns only active voices" do
    result = Voice.active
    assert result.any?
    assert result.all?(&:active?)
  end

  test "active scope excludes inactive voices" do
    result = Voice.active
    assert_not_includes result, voices(:inactive_voice)
  end

  test "for_brand scope returns voices where brand is in allowed_brands" do
    result = Voice.for_brand("b2b")
    assert_includes result, voices(:b2b_only_voice)
    assert_includes result, voices(:standard_voice)
  end

  test "for_brand scope excludes voices not in allowed_brands" do
    # b2b_only_voice has allowed_brands: [b2b] only
    result = Voice.for_brand("b2c")
    assert_not_includes result, voices(:b2b_only_voice)
  end

  test "for_tier scope returns voices with min_tier <= given integer" do
    # standard_voice min_tier: 0, pro_voice min_tier: 1
    result = Voice.for_tier(0)
    assert_includes result, voices(:standard_voice)
    assert_not_includes result, voices(:pro_voice)
  end

  test "for_tier(1) returns both standard and pro voices" do
    result = Voice.for_tier(1)
    assert_includes result, voices(:standard_voice)
    assert_includes result, voices(:pro_voice)
  end

  test "ordered scope returns voices ordered by display_order" do
    result = Voice.ordered
    orders = result.map(&:display_order)
    assert_equal orders.sort, orders
  end

  # ---------------------------------------------------------------------------
  # Predicates
  # ---------------------------------------------------------------------------
  test "standard_tier? returns true when min_tier is 0" do
    voice = voices(:standard_voice)
    assert voice.standard_tier?
  end

  test "standard_tier? returns false when min_tier is 1" do
    voice = voices(:pro_voice)
    assert_not voice.standard_tier?
  end

  test "pro_only? returns true when min_tier is 1" do
    voice = voices(:pro_voice)
    assert voice.pro_only?
  end

  test "pro_only? returns false when min_tier is 0" do
    voice = voices(:standard_voice)
    assert_not voice.pro_only?
  end
end
