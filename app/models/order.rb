# frozen_string_literal: true

class Order < ApplicationRecord
  STATUSES = %w[
    pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed
    lyrics_approved music_generating preview_ready music_failed
    approved cancelled refunded
  ].freeze

  BRANDS            = %w[b2b].freeze
  CURRENCIES        = %w[EUR BRL].freeze
  APPROVED_VARIANTS = %w[a b].freeze

  include Brandable

  # Virtual attribute used by the approve_lyrics guard
  attr_accessor :current_lyrics_draft_id

  # AASM State Machine
  include AASM

  aasm column: :status, requires_new_transaction: false do
    state :pending, initial: true
    state :payment_failed
    state :paid
    state :lyrics_drafting
    state :lyrics_ready
    state :lyrics_failed
    state :lyrics_approved
    state :music_generating
    state :preview_ready
    state :music_failed
    state :approved
    state :cancelled
    state :refunded

    event :mark_paid, after_commit: :enqueue_post_payment_generation do
      transitions from: :pending, to: :paid
    end

    event :start_lyrics_generation do
      transitions from: :paid, to: :lyrics_drafting
    end

    event :lyrics_drafted do
      transitions from: :lyrics_drafting, to: :lyrics_ready
    end

    event :approve_lyrics, after: :lock_lyrics_and_start_music do
      transitions from: :lyrics_ready, to: :lyrics_approved,
                  guard: :has_unapproved_lyrics_draft?
    end

    event :start_music_generation do
      transitions from: :lyrics_approved, to: :music_generating
    end

    event :start_soundtrack_generation do
      transitions from: :paid, to: :music_generating
    end

    event :music_ready do
      transitions from: :music_generating, to: :preview_ready
    end

    event :approve_music do
      transitions from: :preview_ready, to: :approved
    end

    event :regenerate_music do
      transitions from: :preview_ready, to: :music_generating
    end

    event :fail_lyrics, after_commit: :notify_admin do
      transitions from: :lyrics_drafting, to: :lyrics_failed
    end

    event :fail_music, after_commit: :notify_admin do
      transitions from: :music_generating, to: :music_failed
    end

    event :cancel, after: :record_cancellation_timestamp do
      transitions from: %i[pending payment_failed paid lyrics_drafting lyrics_ready lyrics_failed music_failed],
                  to: :cancelled
    end

    event :refund do
      transitions from: :cancelled, to: :refunded
    end
  end

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
  validates :status, inclusion: { in: STATUSES }

  validate :tier_valid_for_brand
  validate :locale_valid_for_brand
  validate :regen_limits_not_exceeded

  # Associations
  belongs_to :user, optional: true
  has_one    :briefing,                dependent: :destroy
  has_one    :campaign,                dependent: :destroy
  has_one    :soundtrack_input,        dependent: :destroy
  has_many   :briefing_messages,       -> { chronological }, dependent: :destroy
  has_many   :lyrics_drafts,           dependent: :destroy
  has_many   :music_generations,       dependent: :destroy
  has_many   :generation_jobs,         dependent: :destroy
  has_many   :generation_costs,        dependent: :destroy
  has_many   :order_assets,            dependent: :destroy
  has_many   :stripe_events,           dependent: :nullify
  has_many   :refund_requests,         dependent: :destroy
  belongs_to :approved_lyrics_draft,   class_name: "LyricsDraft",      optional: true
  belongs_to :approved_music_generation, class_name: "MusicGeneration", optional: true
  belongs_to :favorite_music_asset, class_name: "OrderAsset", optional: true

  # Scopes
  scope :for_brand,       ->(b) { where(brand: b) }
  scope :recent,          -> { order(created_at: :desc) }
  scope :pending_payment, -> { where(status: "pending") }

  # Methods
  def tier_config
    BRANDS_CONFIG.dig(brand&.to_sym, :tiers, tier&.to_sym)
  end

  def lyrics_regen_remaining
    lyrics_regen_limit - lyrics_regen_used
  end

  def lyrics_regen_exhausted?
    lyrics_regen_used >= lyrics_regen_limit
  end

  def current_draft
    lyrics_drafts.order(version: :desc).first
  end

  def music_regen_remaining
    return [Campaigns::MusicRounds::LIMIT - completed_music_rounds, 0].max if campaign
    music_regen_limit - music_regen_used
  end

  def completed_music_rounds
    music_generations.completed.count
  end

  def all_music_assets
    order_assets.where(kind: "music_variant").joins(:music_generation)
      .where(music_generations: { status: "completed" }).order(:music_generation_id, :variant_index)
  end

  def lyrics_editable?
    %w[lyrics_ready preview_ready music_failed].include?(status) && lyrics_revision_token.blank?
  end

  def music_variant_assets
    assets = order_assets.where(kind: "music_variant")
    latest = assets.order(id: :desc).first
    return assets.none unless latest
    assets.where(music_generation_id: latest.music_generation_id).order(:variant_index)
  end

  def creation_version
    [status, lyrics_drafts.maximum(:id), lyrics_regen_used, music_regen_used, favorite_music_asset_id, lyrics_revision_token, lyrics_revision_error,
      order_assets.maximum(:updated_at)&.iso8601(6), campaign&.updated_at&.iso8601(6),
      music_generations.order(:iteration).last&.error_code].join(":")
  end

  # Predicates
  def guest_order?
    user.nil? || user.guest?
  end

  def soundtrack_order?
    tier_config&.dig(:includes_soundtrack) && soundtrack_input.present?
  end

  private

  def brand_value
    brand
  end

  def has_unapproved_lyrics_draft?
    return false if current_lyrics_draft_id.blank?
    draft = lyrics_drafts.find_by(id: current_lyrics_draft_id)
    return false unless draft
    !draft.is_approved
  end

  def lock_lyrics_and_start_music
    draft = lyrics_drafts.find(current_lyrics_draft_id)
    draft.update!(is_approved: true, is_locked: true, approved_at: Time.current)
    self.approved_lyrics_draft_id = draft.id
    self.approved_at = Time.current
    save!
    # Music generation is enqueued asynchronously so the order remains in
    # lyrics_approved state after approval.  The job is responsible for calling
    # start_music_generation! and kicking off the Mureka pipeline.
    GenerateMusicJob.perform_later(id)
  end

  def enqueue_post_payment_generation
    if soundtrack_order?
      UploadSoundtrackInputToMurekaJob.perform_later(id)
    else
      GenerateLyricsJob.perform_later(id)
    end
  end

  def enqueue_lyrics_generation
    GenerateLyricsJob.perform_later(id)
  end

  def notify_admin
    Rails.logger.warn "[Order ##{id}] entered failed state: #{status}"
  end

  def record_cancellation_timestamp
    update_columns(cancelled_at: Time.current)
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
