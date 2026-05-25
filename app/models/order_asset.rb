# frozen_string_literal: true

class OrderAsset < ApplicationRecord
  KINDS = %w[final_mp3 final_wav stems_zip lyrics_pdf].freeze

  # Validations
  validates :kind,        presence: true, inclusion: { in: KINDS }
  validates :storage_key, presence: true

  # Associations
  belongs_to :order
  belongs_to :music_generation, optional: true

  # Scopes
  scope :for_kind, ->(kind) { where(kind: kind) }
  scope :mp3s,     -> { where(kind: "final_mp3") }
  scope :wavs,     -> { where(kind: "final_wav") }

  # Predicates
  def mp3?
    kind == "final_mp3"
  end

  def wav?
    kind == "final_wav"
  end

  def stems?
    kind == "stems_zip"
  end

  def pdf?
    kind == "lyrics_pdf"
  end
end
