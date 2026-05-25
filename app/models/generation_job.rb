# frozen_string_literal: true

class GenerationJob < ApplicationRecord
  PROVIDERS = %w[anthropic mureka].freeze
  STEPS     = %w[lyrics_initial lyrics_regen lyrics_refine music_generate].freeze
  STATUSES  = %w[pending success failed].freeze

  include Statusable

  # Validations
  validates :provider, inclusion: { in: PROVIDERS }
  validates :step,     inclusion: { in: STEPS }
  validates :model,    presence: true

  # Associations
  belongs_to :order
  belongs_to :lyrics_draft, optional: true

  # Scopes
  scope :successful, -> { where(status: "success") }
  scope :failed,     -> { where(status: "failed") }
  scope :for_step,   ->(step) { where(step: step) }

  # Predicates
  STATUSES.each do |s|
    define_method(:"#{s}?") { status == s }
  end
end
