# frozen_string_literal: true

class EmailDelivery < ApplicationRecord
  TEMPLATES = %w[
    order_confirmation lyrics_ready preview_ready
    order_delivered refund_processed order_failed
  ].freeze

  STATUSES = %w[queued sent failed opened clicked].freeze
  BRANDS   = %w[b2b b2c].freeze

  include Statusable

  # Validations
  validates :template,        presence: true, inclusion: { in: TEMPLATES }
  validates :recipient_email, presence: true,
                              format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :locale,          presence: true
  validates :brand,           presence: true, inclusion: { in: BRANDS }

  # Associations
  belongs_to :order, optional: true
  belongs_to :user,  optional: true

  # Scopes
  scope :queued,        -> { where(status: "queued") }
  scope :sent,          -> { where(status: "sent") }
  scope :failed,        -> { where(status: "failed") }
  scope :for_template,  ->(tmpl) { where(template: tmpl) }

  # Predicates
  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end

  def delivered?
    %w[sent opened clicked].include?(status)
  end
end
