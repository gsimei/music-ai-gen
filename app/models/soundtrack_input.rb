# frozen_string_literal: true

class SoundtrackInput < ApplicationRecord
  belongs_to :order

  has_one_attached :file

  INPUT_TYPES   = %w[image video].freeze
  FILE_STATUSES = %w[pending ready failed].freeze

  validates :input_type,  presence: true, inclusion: { in: INPUT_TYPES }
  validates :storage_key, presence: true

  def video?  = input_type == "video"
  def image?  = input_type == "image"
  def ready?  = mureka_file_status == "ready"
  def failed? = mureka_file_status == "failed"
end
