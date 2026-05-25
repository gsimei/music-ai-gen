# frozen_string_literal: true

class Briefing < ApplicationRecord
  # Validations
  validates :about, presence: true
  validates :music_style, presence: true
  validates :language, presence: true
  validates :target_duration_seconds,
            numericality: { greater_than_or_equal_to: 15, less_than_or_equal_to: 600 },
            allow_nil: true

  validate :language_supported

  # Associations
  belongs_to :order
  belongs_to :voice, optional: true

  private

  def language_supported
    return if language.blank?
    all_locales = BRANDS_CONFIG.values.flat_map { |b| b[:supported_locales] }.uniq.map(&:to_s)
    errors.add(:language, :inclusion) unless all_locales.include?(language)
  end
end
