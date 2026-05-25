# frozen_string_literal: true

class RefundRequest < ApplicationRecord
  STATUSES          = %w[pending approved denied processed].freeze
  REASON_CATEGORIES = %w[quality_issue late_delivery wrong_voice technical not_as_expected other].freeze

  include Statusable

  # Validations
  validates :reason,          presence: true
  validates :reason_category, inclusion: { in: REASON_CATEGORIES }, allow_nil: true

  # Associations
  belongs_to :order
  belongs_to :user
  belongs_to :resolved_by, class_name: "User", optional: true

  # Scopes
  scope :pending,  -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :denied,   -> { where(status: "denied") }

  # Predicates
  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end

  def resolved?
    resolved_at.present?
  end
end
