# frozen_string_literal: true

class OrderAsset < ApplicationRecord
  has_one_attached :audio
  has_one_attached :campaign_audio
  has_one_attached :audition_audio

  def audition_ready?
    campaign_preview_ready? && audition_audio.attached? &&
      audition_audio.blob.metadata["source_blob_id"] == campaign_audio.blob.id &&
      audition_audio.blob.metadata["preview_revision"] == preview_revision &&
      audition_audio.blob.metadata["watermark_version"] == Campaigns::AudioAudition::VERSION
  end

  def approved_for_delivery?
    music_variant? && music_generation_id.present? && variant_index.in?([0, 1]) &&
      order.approved? && order.approved_music_generation_id == music_generation_id &&
      order.approved_variant == ("a".ord + variant_index).chr
  end

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
    Rails.application.routes.url_helpers.order_audio_preview_path(order, asset_id: id) if audition_ready?
  end

  def playback_url
    if order.campaign
      return Rails.application.routes.url_helpers.order_audio_final_path(order, asset_id: id) if approved_for_delivery? && audio.attached?
      return nil
    end
    audio.attached? ? Rails.application.routes.url_helpers.rails_blob_path(audio, only_path: true) : url.presence || provider_url
  end

  def listening_url
    order.campaign ? campaign_playback_url : playback_url
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
