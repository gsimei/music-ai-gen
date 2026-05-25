# frozen_string_literal: true

require "test_helper"

# Tests for Orders::CreateDraftService — creates an Order and a Briefing inside
# a single database transaction at the end of the wizard (Step 5).
#
# Service interface:
#   Orders::CreateDraftService.call(
#     brand:    "b2c",            # from @current_brand
#     locale:   "it",             # from I18n.locale.to_s
#     user_id:  user.id | nil,    # nil for guests
#     wizard_data: {              # merged session hash from steps 1–5
#       delivery_email: ...,
#       about: ...,
#       recipient: ...,
#       occasion: ...,
#       music_style: ...,
#       mood: ...,
#       tempo: ...,
#       target_duration_seconds: ...,
#       keywords: ...,
#       avoid: ...,
#       voice_id: ...,
#       tier: ...
#     }
#   )
#
# Returns ServiceResult:
#   success? => true,  value: order (with briefing loaded)
#   success? => false, errors: ActiveModel::Errors or symbol
class Orders::CreateDraftServiceTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Happy path — b2c standard tier
  # ---------------------------------------------------------------------------

  test "creates order and briefing in transaction for b2c standard" do
    voice = voices(:standard_voice)

    assert_difference -> { Order.count } => 1, -> { Briefing.count } => 1 do
      result = Orders::CreateDraftService.call(
        brand: "b2c",
        locale: "it",
        user_id: nil,
        wizard_data: {
          delivery_email: "new@example.com",
          about: "Uma musica para o aniversario",
          music_style: "pop",
          voice_id: voice.id,
          tier: "standard"
        }
      )
      assert result.success?, "Expected success but got: #{result.errors.inspect}"
    end
  end

  test "returns created order as result value" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica para o aniversario",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_kind_of Order, result.value
    assert result.value.persisted?
  end

  # ---------------------------------------------------------------------------
  # Reference format ORD-YYYY-XXXXX
  # ---------------------------------------------------------------------------

  test "generated reference matches ORD-YYYY-XXXXX format" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica para o aniversario",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_match(/\AORD-\d{4}-[A-Z0-9]{5}\z/, result.value.reference)
  end

  test "generated reference contains the current year" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica para o aniversario",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    year = Time.current.year.to_s
    assert_includes result.value.reference, "ORD-#{year}-"
  end

  test "two successive calls generate distinct references" do
    voice = voices(:standard_voice)

    result1 = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "first@example.com",
        about: "Primeira musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    result2 = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "second@example.com",
        about: "Segunda musica",
        music_style: "rock",
        voice_id: voice.id,
        tier: "standard"
      }
    )

    assert result1.success?
    assert result2.success?
    assert_not_equal result1.value.reference, result2.value.reference
  end

  # ---------------------------------------------------------------------------
  # Price and limits from BRANDS_CONFIG
  # ---------------------------------------------------------------------------

  test "price_cents is resolved from BRANDS_CONFIG for b2c standard" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    expected = BRANDS_CONFIG.dig(:b2c, :tiers, :standard, :price_cents)
    assert_equal expected, result.value.price_cents
  end

  test "price_cents is resolved from BRANDS_CONFIG for b2c pro" do
    voice = voices(:pro_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "pro"
      }
    )
    assert result.success?
    expected = BRANDS_CONFIG.dig(:b2c, :tiers, :pro, :price_cents)
    assert_equal expected, result.value.price_cents
  end

  test "price_cents is resolved from BRANDS_CONFIG for b2b starter" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2b",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "business@example.com",
        about: "Jingle para restaurante",
        music_style: "acoustic",
        voice_id: voice.id,
        tier: "starter"
      }
    )
    assert result.success?
    expected = BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :price_cents)
    assert_equal expected, result.value.price_cents
  end

  test "lyrics_regen_limit is resolved from BRANDS_CONFIG" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    expected = BRANDS_CONFIG.dig(:b2c, :tiers, :standard, :lyrics_regen_limit)
    assert_equal expected, result.value.lyrics_regen_limit
  end

  test "music_regen_limit is resolved from BRANDS_CONFIG" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    expected = BRANDS_CONFIG.dig(:b2c, :tiers, :standard, :music_regen_limit)
    assert_equal expected, result.value.music_regen_limit
  end

  # ---------------------------------------------------------------------------
  # Brand and locale are set on Order from service arguments, not wizard_data
  # ---------------------------------------------------------------------------

  test "order.brand is taken from service brand argument" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_equal "b2c", result.value.brand
  end

  # ---------------------------------------------------------------------------
  # Briefing language = I18n.locale.to_s (not from user params)
  # ---------------------------------------------------------------------------

  test "briefing language is set to locale argument (not user-supplied)" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "en",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_equal "en", result.value.briefing.language
  end

  test "briefing language ignores any language key in wizard_data" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard",
        language: "fr"          # should be ignored
      }
    )
    assert result.success?
    assert_equal "it", result.value.briefing.language
  end

  # ---------------------------------------------------------------------------
  # Guest order — user_id nil
  # ---------------------------------------------------------------------------

  test "creates order without user when user_id is nil" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "guest@example.com",
        about: "Musica para presente",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_nil result.value.user_id
    assert result.value.guest_order?
  end

  # ---------------------------------------------------------------------------
  # Briefing stores optional fields from wizard_data
  # ---------------------------------------------------------------------------

  test "briefing stores optional fields when provided" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica para o aniversario",
        recipient: "Maria",
        occasion: "birthday",
        music_style: "pop",
        mood: "happy",
        tempo: "moderate",
        target_duration_seconds: 120,
        keywords: "love, family",
        avoid: "sad",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    briefing = result.value.briefing
    assert_equal "Maria", briefing.recipient
    assert_equal "birthday", briefing.occasion
    assert_equal "happy", briefing.mood
    assert_equal "moderate", briefing.tempo
    assert_equal 120, briefing.target_duration_seconds
    assert_equal "love, family", briefing.keywords
    assert_equal "sad", briefing.avoid
  end

  # ---------------------------------------------------------------------------
  # Failure — pro-only voice with standard tier
  # ---------------------------------------------------------------------------

  test "returns failure when pro-only voice is used with standard tier for b2c" do
    pro_voice = voices(:pro_voice)  # min_tier: 1

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: pro_voice.id,
        tier: "standard"           # standard maps to min_tier=0 — pro voice requires min_tier=1
      }
    )
    assert result.failure?
  end

  test "does not persist anything when pro-only voice and standard tier" do
    pro_voice = voices(:pro_voice)

    assert_no_difference [ "Order.count", "Briefing.count" ] do
      Orders::CreateDraftService.call(
        brand: "b2c",
        locale: "it",
        user_id: nil,
        wizard_data: {
          delivery_email: "new@example.com",
          about: "Uma musica",
          music_style: "pop",
          voice_id: pro_voice.id,
          tier: "standard"
        }
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — inactive voice
  # ---------------------------------------------------------------------------

  test "returns failure when voice is inactive" do
    inactive = voices(:inactive_voice)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: inactive.id,
        tier: "standard"
      }
    )
    assert result.failure?
  end

  # ---------------------------------------------------------------------------
  # Failure — voice not allowed for brand
  # ---------------------------------------------------------------------------

  test "returns failure when voice is not allowed for the brand" do
    b2b_voice = voices(:b2b_only_voice)  # allowed_brands: [b2b]

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: b2b_voice.id,
        tier: "standard"
      }
    )
    assert result.failure?
  end

  # ---------------------------------------------------------------------------
  # Failure — invalid tier for brand
  # ---------------------------------------------------------------------------

  test "returns failure when tier is invalid for brand" do
    voice = voices(:standard_voice)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "starter"   # starter is b2b-only
      }
    )
    assert result.failure?
  end

  test "does not persist anything when tier is invalid for brand" do
    voice = voices(:standard_voice)

    assert_no_difference [ "Order.count", "Briefing.count" ] do
      Orders::CreateDraftService.call(
        brand: "b2c",
        locale: "it",
        user_id: nil,
        wizard_data: {
          delivery_email: "new@example.com",
          about: "Uma musica",
          music_style: "pop",
          voice_id: voice.id,
          tier: "starter"
        }
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Failure — missing required wizard_data fields
  # ---------------------------------------------------------------------------

  test "returns failure when delivery_email is missing" do
    voice = voices(:standard_voice)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.failure?
  end

  test "returns failure when about is missing" do
    voice = voices(:standard_voice)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.failure?
  end

  test "returns failure when music_style is missing" do
    voice = voices(:standard_voice)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.failure?
  end

  test "returns failure when voice_id is missing" do
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        tier: "standard"
      }
    )
    assert result.failure?
  end

  test "returns failure when tier is missing" do
    voice = voices(:standard_voice)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id
      }
    )
    assert result.failure?
  end

  # ---------------------------------------------------------------------------
  # Transaction rollback — nothing persisted on any failure
  # ---------------------------------------------------------------------------

  test "nothing is persisted when an inner validation fails" do
    # Use an invalid combination to trigger failure after initial checks pass
    voice = voices(:pro_voice)  # min_tier: 1

    assert_no_difference [ "Order.count", "Briefing.count" ] do
      Orders::CreateDraftService.call(
        brand: "b2c",
        locale: "it",
        user_id: nil,
        wizard_data: {
          delivery_email: "new@example.com",
          about: "Uma musica",
          music_style: "pop",
          voice_id: voice.id,
          tier: "standard"  # tier incompatible with pro voice
        }
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Happy path — authenticated user
  # ---------------------------------------------------------------------------

  test "order is associated with user when user_id is provided" do
    voice = voices(:standard_voice)
    user = users(:customer_b2c)

    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: user.id,
      wizard_data: {
        delivery_email: user.email,
        about: "Uma musica para o aniversario",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_equal user.id, result.value.user_id
  end

  # ---------------------------------------------------------------------------
  # Order status is always 'pending' after creation
  # ---------------------------------------------------------------------------

  test "created order has status pending" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_equal "pending", result.value.status
  end

  # ---------------------------------------------------------------------------
  # Briefing voice association
  # ---------------------------------------------------------------------------

  test "briefing is associated with the selected voice" do
    voice = voices(:standard_voice)
    result = Orders::CreateDraftService.call(
      brand: "b2c",
      locale: "it",
      user_id: nil,
      wizard_data: {
        delivery_email: "new@example.com",
        about: "Uma musica",
        music_style: "pop",
        voice_id: voice.id,
        tier: "standard"
      }
    )
    assert result.success?
    assert_equal voice.id, result.value.briefing.voice_id
  end
end
