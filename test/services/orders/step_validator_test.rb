# frozen_string_literal: true

require "test_helper"

# Tests for Orders::StepValidator — an ActiveModel object that validates
# the fields submitted at each wizard step before they are stored in session.
#
# The validator receives:
#   step   — integer (1..5)
#   brand  — "b2b" | "b2c"  (resolved from host)
#   params — hash of user-submitted fields for this step
#
# It returns an ActiveModel::Errors-compatible object so the controller
# can re-render the step with inline error messages.
class Orders::StepValidatorTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Step 1 — delivery_email (required), about (required), recipient, occasion
  # ---------------------------------------------------------------------------

  test "step 1 is valid with all required fields present" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: {
        delivery_email: "customer@example.com",
        about: "Uma musica para o aniversario da minha mae"
      }
    )
    assert validator.valid?
    assert_empty validator.errors.full_messages
  end

  test "step 1 is valid with optional fields also present" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: {
        delivery_email: "customer@example.com",
        about: "Uma musica para o aniversario da minha mae",
        recipient: "Maria",
        occasion: "birthday"
      }
    )
    assert validator.valid?
  end

  test "step 1 is invalid without delivery_email" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: { about: "Uma musica para o aniversario" }
    )
    assert_not validator.valid?
    assert validator.errors[:delivery_email].any?
  end

  test "step 1 is invalid with malformed delivery_email" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: {
        delivery_email: "not-an-email",
        about: "Uma musica para o aniversario"
      }
    )
    assert_not validator.valid?
    assert validator.errors[:delivery_email].any?
  end

  test "step 1 is invalid without about" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: { delivery_email: "customer@example.com" }
    )
    assert_not validator.valid?
    assert validator.errors[:about].any?
  end

  test "step 1 does not validate music_style (that is step 2)" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: {
        delivery_email: "customer@example.com",
        about: "Uma musica"
      }
    )
    assert validator.valid?
    assert_empty validator.errors[:music_style]
  end

  # ---------------------------------------------------------------------------
  # Step 2 — music_style (required), mood, tempo, target_duration_seconds
  # ---------------------------------------------------------------------------

  test "step 2 is valid with only music_style present" do
    validator = Orders::StepValidator.new(
      step: 2,
      brand: "b2c",
      params: { music_style: "pop" }
    )
    assert validator.valid?
  end

  test "step 2 is valid with all optional fields also present" do
    validator = Orders::StepValidator.new(
      step: 2,
      brand: "b2c",
      params: {
        music_style: "acoustic",
        mood: "happy",
        tempo: "fast",
        target_duration_seconds: 120
      }
    )
    assert validator.valid?
  end

  test "step 2 is invalid without music_style" do
    validator = Orders::StepValidator.new(
      step: 2,
      brand: "b2c",
      params: { mood: "happy" }
    )
    assert_not validator.valid?
    assert validator.errors[:music_style].any?
  end

  test "step 2 does not validate delivery_email (that is step 1)" do
    validator = Orders::StepValidator.new(
      step: 2,
      brand: "b2c",
      params: { music_style: "pop" }
    )
    assert validator.valid?
    assert_empty validator.errors[:delivery_email]
  end

  # ---------------------------------------------------------------------------
  # Step 3 — keywords, avoid (both optional)
  # ---------------------------------------------------------------------------

  test "step 3 is valid with empty params (all optional)" do
    validator = Orders::StepValidator.new(
      step: 3,
      brand: "b2c",
      params: {}
    )
    assert validator.valid?
  end

  test "step 3 is valid when keywords and avoid are present" do
    validator = Orders::StepValidator.new(
      step: 3,
      brand: "b2c",
      params: { keywords: "love, family", avoid: "sad, dark" }
    )
    assert validator.valid?
  end

  test "step 3 is valid with only keywords" do
    validator = Orders::StepValidator.new(
      step: 3,
      brand: "b2c",
      params: { keywords: "love" }
    )
    assert validator.valid?
  end

  # ---------------------------------------------------------------------------
  # Step 4 — voice_id (required, active, allowed for brand)
  # ---------------------------------------------------------------------------

  test "step 4 is valid with an active voice allowed for the brand" do
    voice = voices(:standard_voice)  # active, allowed_brands: [b2b, b2c], min_tier: 0
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2c",
      params: { voice_id: voice.id }
    )
    assert validator.valid?
  end

  test "step 4 is valid with a pro-only voice when it is allowed for the brand" do
    # Tier compatibility is checked at CreateDraftService level, not here.
    # StepValidator only checks: active + allowed for brand.
    voice = voices(:pro_voice)  # active, min_tier: 1, allowed_brands: [b2b, b2c]
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2c",
      params: { voice_id: voice.id }
    )
    assert validator.valid?
  end

  test "step 4 is invalid without voice_id" do
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2c",
      params: {}
    )
    assert_not validator.valid?
    assert validator.errors[:voice_id].any?
  end

  test "step 4 is invalid with an inactive voice" do
    voice = voices(:inactive_voice)  # active: false
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2c",
      params: { voice_id: voice.id }
    )
    assert_not validator.valid?
    assert validator.errors[:voice_id].any?
  end

  test "step 4 is invalid with a voice not allowed for the brand" do
    voice = voices(:b2b_only_voice)  # allowed_brands: [b2b] only
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2c",
      params: { voice_id: voice.id }
    )
    assert_not validator.valid?
    assert validator.errors[:voice_id].any?
  end

  test "step 4 is invalid with a non-existent voice_id" do
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2c",
      params: { voice_id: 999_999_999 }
    )
    assert_not validator.valid?
    assert validator.errors[:voice_id].any?
  end

  test "step 4 b2b brand accepts voice allowed for b2b" do
    voice = voices(:b2b_only_voice)  # allowed_brands: [b2b], active: true
    validator = Orders::StepValidator.new(
      step: 4,
      brand: "b2b",
      params: { voice_id: voice.id }
    )
    assert validator.valid?
  end

  # ---------------------------------------------------------------------------
  # Step 5 — tier (required, valid for brand from BRANDS_CONFIG)
  # ---------------------------------------------------------------------------

  test "step 5 is valid with tier standard for brand b2c" do
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2c",
      params: { tier: "standard" }
    )
    assert validator.valid?
  end

  test "step 5 is valid with tier pro for brand b2c" do
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2c",
      params: { tier: "pro" }
    )
    assert validator.valid?
  end

  test "step 5 is valid with tier starter for brand b2b" do
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2b",
      params: { tier: "starter" }
    )
    assert validator.valid?
  end

  test "step 5 is valid with tier pro for brand b2b" do
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2b",
      params: { tier: "pro" }
    )
    assert validator.valid?
  end

  test "step 5 is invalid without tier" do
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2c",
      params: {}
    )
    assert_not validator.valid?
    assert validator.errors[:tier].any?
  end

  test "step 5 is invalid when tier does not exist for brand b2c" do
    # 'starter' is a b2b tier, not b2c
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2c",
      params: { tier: "starter" }
    )
    assert_not validator.valid?
    assert validator.errors[:tier].any?
  end

  test "step 5 is invalid when tier does not exist for brand b2b" do
    # 'standard' is a b2c tier, not b2b
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2b",
      params: { tier: "standard" }
    )
    assert_not validator.valid?
    assert validator.errors[:tier].any?
  end

  test "step 5 is invalid with completely unknown tier" do
    validator = Orders::StepValidator.new(
      step: 5,
      brand: "b2c",
      params: { tier: "platinum" }
    )
    assert_not validator.valid?
    assert validator.errors[:tier].any?
  end

  # ---------------------------------------------------------------------------
  # Errors object is accessible and enumerable
  # ---------------------------------------------------------------------------

  test "errors is an ActiveModel::Errors instance" do
    validator = Orders::StepValidator.new(
      step: 1,
      brand: "b2c",
      params: {}
    )
    validator.valid?
    assert_kind_of ActiveModel::Errors, validator.errors
  end
end
