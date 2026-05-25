# frozen_string_literal: true

class Order < ApplicationRecord
  STATUSES = %w[
    pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
    lyrics_approved music_generating preview_ready music_failed
    approved delivered cancelled refunded
  ].freeze

  BRANDS            = %w[b2b b2c].freeze
  CURRENCIES        = %w[EUR].freeze
  APPROVED_VARIANTS = %w[a b].freeze

  include Statusable
  include Brandable

  # Validations
  validates :reference, presence: true,
                        uniqueness: true,
                        format: { with: /\AORD-\d{4}-[A-Z0-9]{5}\z/ }
  validates :brand, presence: true, inclusion: { in: BRANDS }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :delivery_email, presence: true,
                             format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :locale, presence: true
  validates :price_cents, presence: true,
                          numericality: { greater_than: 0 }
  validates :approved_variant, inclusion: { in: APPROVED_VARIANTS }, allow_nil: true

  validate :tier_valid_for_brand
  validate :locale_valid_for_brand
  validate :regen_limits_not_exceeded

  # Associations
  belongs_to :user, optional: true
  has_one    :briefing,                dependent: :destroy
  has_many   :lyrics_drafts,           dependent: :destroy
  has_many   :music_generations,       dependent: :destroy
  has_many   :generation_jobs,         dependent: :destroy
  has_many   :order_assets,            dependent: :destroy
  has_many   :stripe_events,           dependent: :nullify
  has_many   :refund_requests,         dependent: :destroy
  has_many   :email_deliveries,        dependent: :nullify
  belongs_to :approved_lyrics_draft,   class_name: "LyricsDraft",      optional: true
  belongs_to :approved_music_generation, class_name: "MusicGeneration", optional: true

  # Scopes
  scope :paid,            -> { where(status: "paid") }
  scope :delivered,       -> { where(status: "delivered") }
  scope :for_brand,       ->(b) { where(brand: b) }
  scope :recent,          -> { order(created_at: :desc) }
  scope :pending_payment, -> { where(status: "pending") }

  # Status predicates (14 manual)
  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end

  # Methods
  def tier_config
    BRANDS_CONFIG.dig(brand&.to_sym, :tiers, tier&.to_sym)
  end

  def lyrics_regen_remaining
    lyrics_regen_limit - lyrics_regen_used
  end

  def music_regen_remaining
    music_regen_limit - music_regen_used
  end

  # Predicates
  def guest_order?
    user.nil? || user.guest?
  end

  private

  def brand_value
    brand
  end

  def tier_valid_for_brand
    return unless BRANDS.include?(brand)
    return if tier.blank?
    return if BRANDS_CONFIG.dig(brand.to_sym, :tiers, tier.to_sym).present?
    errors.add(:tier, :inclusion)
  end

  def locale_valid_for_brand
    return unless BRANDS.include?(brand)
    return if locale.blank?
    supported = BRANDS_CONFIG.dig(brand.to_sym, :supported_locales)&.map(&:to_s) || []
    errors.add(:locale, :inclusion) unless supported.include?(locale)
  end

  def regen_limits_not_exceeded
    if lyrics_regen_used.present? && lyrics_regen_limit.present?
      if lyrics_regen_used > lyrics_regen_limit
        errors.add(:lyrics_regen_used, :less_than_or_equal_to, count: lyrics_regen_limit)
      end
    end
    if music_regen_used.present? && music_regen_limit.present?
      if music_regen_used > music_regen_limit
        errors.add(:music_regen_used, :less_than_or_equal_to, count: music_regen_limit)
      end
    end
  end
end
