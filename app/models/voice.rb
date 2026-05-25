# frozen_string_literal: true

class Voice < ApplicationRecord
  PROVIDERS      = %w[mureka].freeze
  GENDERS        = %w[male female neutral].freeze
  VALID_BRANDS   = %w[b2b b2c].freeze
  MIN_TIER_RANGE = (0..1).freeze

  # Validations
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :name, presence: true
  validates :slug, presence: true,
                   uniqueness: true,
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validates :min_tier, inclusion: { in: MIN_TIER_RANGE }

  validate :allowed_brands_subset_of_valid_brands
  validate :external_id_or_mureka_prompt_present

  # Associations
  has_many :briefings, dependent: :nullify
  has_many :music_generations, dependent: :restrict_with_error

  # Scopes
  scope :active,    -> { where(active: true) }
  scope :for_brand, ->(brand_str) { where("? = ANY(allowed_brands)", brand_str) }
  scope :for_tier,  ->(tier_int)  { where("min_tier <= ?", tier_int) }
  scope :ordered,   -> { order(display_order: :asc) }

  # Predicates
  def standard_tier?
    min_tier == 0
  end

  def pro_only?
    min_tier == 1
  end

  private

  def allowed_brands_subset_of_valid_brands
    return if allowed_brands.blank?
    invalid = allowed_brands - VALID_BRANDS
    errors.add(:allowed_brands, :inclusion) if invalid.any?
  end

  def external_id_or_mureka_prompt_present
    return if external_id.present? || mureka_prompt.present?
    errors.add(:base, :invalid, message: "must have external_id or mureka_prompt")
  end
end
