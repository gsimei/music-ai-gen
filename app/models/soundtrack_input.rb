# frozen_string_literal: true

class SoundtrackInput < ApplicationRecord
  belongs_to :order

  has_one_attached :file

  INPUT_TYPES   = %w[image video].freeze
  FILE_STATUSES = %w[pending uploading ready failed].freeze
  MAX_FILE_SIZE = 100.megabytes
  EXTENSIONS = { "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp",
                 "video/mp4" => ".mp4", "video/quicktime" => ".mov", "video/webm" => ".webm" }.freeze
  CONTENT_TYPES = EXTENSIONS.keys.freeze

  validates :input_type,  presence: true, inclusion: { in: INPUT_TYPES }
  validates :storage_key, presence: true
  validate :supported_file

  def self.acceptable_upload?(upload)
    upload.is_a?(ActionDispatch::Http::UploadedFile) &&
      upload.size.positive? && upload.size <= MAX_FILE_SIZE && CONTENT_TYPES.include?(upload.content_type)
  end

  def processable_file?
    file.attached? && file.blob.byte_size.positive? && file.blob.byte_size <= MAX_FILE_SIZE &&
      CONTENT_TYPES.include?(file.blob.content_type) && file.blob.content_type.start_with?("#{input_type}/")
  end

  def video?  = input_type == "video"
  def image?  = input_type == "image"
  def ready?  = mureka_file_status == "ready"
  def failed? = mureka_file_status == "failed"

  private

  def supported_file
    errors.add(:file, :invalid) if file.attached? && !processable_file?
  end
end
