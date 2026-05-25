# frozen_string_literal: true

module Orders
  # Creates an Order and a Briefing inside a single database transaction
  # at the end of the wizard (Step 5 submission).
  #
  # Validates:
  #   - All required wizard_data fields are present
  #   - Tier is valid for the brand (per BRANDS_CONFIG)
  #   - Voice exists, is active, and is allowed for the brand
  #   - Voice min_tier is compatible with the chosen tier
  #
  # On success, returns ServiceResult with the persisted Order (with briefing loaded).
  # On any failure, returns ServiceResult with errors. Nothing is persisted.
  #
  # Tier → min_tier integer mapping:
  #   b2c "standard" → 0
  #   b2b "starter"  → 0
  #   any "pro"      → 1
  class CreateDraftService < BaseService
    TIER_MIN_TIER_MAP = {
      "standard" => 0,
      "starter"  => 0,
      "pro"      => 1
    }.freeze

    attribute :wizard_data, default: -> { {} }
    attribute :brand,   :string
    attribute :locale,  :string
    attribute :user_id, :integer

    # Declare error key attributes so ActiveModel::Errors can introspect them.
    attr_accessor :delivery_email, :about, :music_style, :voice_id, :tier

    def call
      validate_required_fields!
      validate_tier!
      validate_voice!
      return failure_result(errors) if errors.any?

      tier_config = BRANDS_CONFIG.dig(brand.to_sym, :tiers, tier.to_sym)

      order = nil
      ActiveRecord::Base.transaction do
        order = Order.create!(
          reference:          ReferenceGenerator.generate!,
          brand:              brand,
          locale:             locale,
          delivery_email:     wizard_data_value(:delivery_email),
          tier:               tier,
          price_cents:        tier_config[:price_cents],
          lyrics_regen_limit: tier_config[:lyrics_regen_limit],
          music_regen_limit:  tier_config[:music_regen_limit],
          user_id:            user_id,
          status:             "pending"
        )

        Briefing.create!(
          order:                   order,
          about:                   wizard_data_value(:about),
          music_style:             wizard_data_value(:music_style),
          language:                locale,
          voice_id:                wizard_data_value(:voice_id),
          recipient:               wizard_data_value(:recipient),
          occasion:                wizard_data_value(:occasion),
          mood:                    wizard_data_value(:mood),
          tempo:                   wizard_data_value(:tempo),
          target_duration_seconds: wizard_data_value(:target_duration_seconds),
          keywords:                wizard_data_value(:keywords),
          avoid:                   wizard_data_value(:avoid)
        )
      end

      order.reload
      success_result(order)
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, e.message)
      failure_result(errors)
    end

    private

    def wizard_data_value(key)
      wizard_data[key] || wizard_data[key.to_s]
    end

    def tier
      @tier ||= wizard_data_value(:tier).to_s
    end

    def voice
      @voice ||= Voice.find_by(id: wizard_data_value(:voice_id))
    end

    def validate_required_fields!
      %i[delivery_email about music_style voice_id tier].each do |field|
        val = wizard_data_value(field)
        errors.add(field, :blank) if val.blank?
      end
    end

    def validate_tier!
      return if errors[:tier].any?

      valid_tiers = BRANDS_CONFIG.dig(brand.to_sym, :tiers)&.keys&.map(&:to_s) || []
      errors.add(:tier, :inclusion) unless valid_tiers.include?(tier)
    end

    def validate_voice!
      return if errors[:voice_id].any?

      if voice.nil?
        errors.add(:voice_id, :invalid)
        return
      end

      unless voice.active
        errors.add(:voice_id, :invalid)
        return
      end

      unless Array(voice.allowed_brands).include?(brand.to_s)
        errors.add(:voice_id, :invalid)
        return
      end

      # Check voice tier compatibility: voice.min_tier must be <= tier's min_tier integer
      tier_min = TIER_MIN_TIER_MAP.fetch(tier, 0)
      if voice.min_tier > tier_min
        errors.add(:voice_id, :invalid)
      end
    end
  end
end
