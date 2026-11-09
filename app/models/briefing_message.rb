# frozen_string_literal: true

class BriefingMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :order

  validates :role,    inclusion: { in: ROLES }
  validates :content, presence: true

  scope :chronological, -> { order(:created_at, :id) }
end
