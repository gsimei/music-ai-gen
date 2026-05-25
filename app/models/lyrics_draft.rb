# frozen_string_literal: true

class LyricsDraft < ApplicationRecord
  SOURCES = %w[ai_generated user_edited regenerated].freeze

  # Validations
  validates :version, presence: true,
                      uniqueness: { scope: :order_id },
                      numericality: { greater_than: 0, only_integer: true }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :content, presence: true

  validate :parent_required_when_regenerated

  # Associations
  belongs_to :order
  belongs_to :parent_draft, class_name: "LyricsDraft", optional: true
  has_many   :child_drafts,
             class_name:  "LyricsDraft",
             foreign_key: :parent_draft_id,
             dependent:   :nullify
  has_many   :music_generations, dependent: :restrict_with_error
  has_many   :generation_jobs,   dependent: :nullify

  # Scopes
  scope :approved, -> { where(is_approved: true) }
  scope :locked,   -> { where(is_locked: true) }
  scope :latest_for, ->(order_id) { where(order_id: order_id).order(version: :desc).first }

  # Predicates
  def approved?
    is_approved
  end

  def locked?
    is_locked
  end

  def regenerated?
    source == "regenerated"
  end

  def ai_generated?
    source == "ai_generated"
  end

  private

  def parent_required_when_regenerated
    return unless source == "regenerated"
    errors.add(:parent_draft_id, :blank) if parent_draft_id.blank?
  end
end
