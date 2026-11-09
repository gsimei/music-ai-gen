# frozen_string_literal: true

class OrderAsset < ApplicationRecord
  has_one_attached :audio
  has_one_attached :campaign_audio

  def campaign_preview_ready?
    campaign_preview_status == "ready" && campaign_audio.attached? && campaign_audio.blob.metadata.fetch("preview_revision", 0) == preview_revision
  end

  def track_duration_seconds
    archived_duration = campaign_audio.attached? && campaign_audio.blob.metadata["track_duration_seconds"]
    (archived_duration || duration_ms.to_f / 1000).to_f
  end

  def excerpt_max_start
    [track_duration_seconds - Campaigns::AudioPreview::MAX_DURATION, 0].max.floor(2)
  end

  def campaign_playback_url
    Rails.application.routes.url_helpers.rails_blob_path(campaign_audio, only_path: true) if campaign_preview_ready?
  end

  def playback_url
    audio.attached? ? Rails.application.routes.url_helpers.rails_blob_path(audio, only_path: true) : url.presence || provider_url
  end

  KINDS = %w[final_mp3 final_wav stems_zip lyrics_pdf].freeze
  PROVIDER_KINDS = %w[music_variant soundtrack_video].freeze
  ALL_KINDS = (KINDS + PROVIDER_KINDS).freeze

  # Validations
  validates :kind,        presence: true, inclusion: { in: ALL_KINDS }
  validates :storage_key, presence: true, unless: -> { music_variant? || soundtrack_video? }

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

  def music_variant?
    kind == "music_variant"
  end

  def soundtrack_video?
    kind == "soundtrack_video"
  end
end
