# frozen_string_literal: true

class MusicGeneration < ApplicationRecord
  STATUSES  = %w[pending processing completed failed cancelled].freeze
  PROVIDERS = %w[mureka].freeze

  include Statusable

  # Validations
  validates :iteration, presence: true,
                        uniqueness: { scope: :order_id },
                        numericality: { greater_than: 0, only_integer: true }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :music_style, presence: true

  # Associations
  belongs_to :order
  belongs_to :voice
  belongs_to :lyrics_draft
  belongs_to :parent_generation,
             class_name: "MusicGeneration",
             optional:   true
  has_many   :child_generations,
             class_name:  "MusicGeneration",
             foreign_key: :parent_generation_id,
             dependent:   :nullify
  has_many   :order_assets, dependent: :destroy

  # Scopes
  scope :completed, -> { where(status: "completed") }
  scope :pending,   -> { where(status: "pending") }
  scope :failed,    -> { where(status: "failed") }

  # Status predicates (5 manual)
  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end

  # Variant predicates
  def variant_a_complete?
    variant_a_full_url.present?
  end

  def variant_b_complete?
    variant_b_full_url.present?
  end

  def both_variants_complete?
    variant_a_complete? && variant_b_complete?
  end

  # Methods
  def selected_variant_url(variant)
    case variant
    when "a" then variant_a_full_url
    when "b" then variant_b_full_url
    end
  end
end
