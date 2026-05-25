# frozen_string_literal: true

module Orders
  # Validates the fields submitted at a single wizard step.
  # Accepts step (1-5), brand ("b2b"|"b2c"), and params (hash).
  #
  # Returns an ActiveModel::Errors-compatible object via valid? / errors.
  # Tier compatibility with a chosen voice is NOT validated here —
  # that cross-step check is deferred to CreateDraftService.
  class StepValidator
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :step,   :integer
    attribute :brand,  :string
    attribute :params, default: -> { {} }

    # Declare all field names that can appear in errors so that
    # ActiveModel::Errors can introspect them via respond_to?.
    attr_accessor :delivery_email, :about, :recipient, :occasion,
                  :music_style, :mood, :tempo, :target_duration_seconds,
                  :keywords, :avoid, :voice_id, :tier

    validate :validate_for_step

    private

    def validate_for_step
      case step
      when 1 then validate_step_1
      when 2 then validate_step_2
      when 3 then validate_step_3
      when 4 then validate_step_4
      when 5 then validate_step_5
      end
    end

    # ---------------------------------------------------------------------------
    # Step 1: delivery_email (required + format), about (required)
    # ---------------------------------------------------------------------------

    def validate_step_1
      email = params[:delivery_email].presence || params["delivery_email"].presence

      if email.blank?
        errors.add(:delivery_email, :blank)
      elsif !email.match?(URI::MailTo::EMAIL_REGEXP)
        errors.add(:delivery_email, :invalid)
      end

      about = params[:about].presence || params["about"].presence
      errors.add(:about, :blank) if about.blank?
    end

    # ---------------------------------------------------------------------------
    # Step 2: music_style (required)
    # ---------------------------------------------------------------------------

    def validate_step_2
      music_style = params[:music_style].presence || params["music_style"].presence
      errors.add(:music_style, :blank) if music_style.blank?
    end

    # ---------------------------------------------------------------------------
    # Step 3: all optional — no validations
    # ---------------------------------------------------------------------------

    def validate_step_3
      # keywords and avoid are optional
    end

    # ---------------------------------------------------------------------------
    # Step 4: voice_id (required, voice must be active and allowed for brand)
    # ---------------------------------------------------------------------------

    def validate_step_4
      voice_id = params[:voice_id] || params["voice_id"]

      if voice_id.blank?
        errors.add(:voice_id, :blank)
        return
      end

      voice = Voice.find_by(id: voice_id)

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
      end
    end

    # ---------------------------------------------------------------------------
    # Step 5: tier (required, must be valid for the brand per BRANDS_CONFIG)
    # ---------------------------------------------------------------------------

    def validate_step_5
      tier = params[:tier].presence || params["tier"].presence

      if tier.blank?
        errors.add(:tier, :blank)
        return
      end

      valid_tiers = BRANDS_CONFIG.dig(brand.to_sym, :tiers)&.keys&.map(&:to_s) || []
      unless valid_tiers.include?(tier.to_s)
        errors.add(:tier, :inclusion)
      end
    end
  end
end
