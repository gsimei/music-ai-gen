# frozen_string_literal: true

class StripeEvent < ApplicationRecord
  STATUSES = %w[pending processed failed skipped].freeze

  include Statusable

  # Validations
  validates :stripe_event_id, presence: true, uniqueness: true
  validates :event_type,      presence: true
  validates :payload,         presence: true

  # Associations
  belongs_to :order, optional: true

  # Scopes
  scope :pending,   -> { where(status: "pending") }
  scope :processed, -> { where(status: "processed") }
  scope :failed,    -> { where(status: "failed") }

  # Predicates
  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end

  alias already_processed? processed?
end
