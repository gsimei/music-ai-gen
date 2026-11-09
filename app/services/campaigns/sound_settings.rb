module Campaigns
  class SoundSettings < BaseService
    attribute :order
    attribute :settings
    attribute :expected_settings

    def call
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && order.lyrics_editable?
        return failure_result(:busy) if order.music_generations.where(status: %w[pending processing]).exists?
        return failure_result(:regen_limit_reached) if order.completed_music_rounds >= MusicRounds::LIMIT
        campaign = order.campaign.reload
        return failure_result(:stale_sound_settings) if expected_settings && campaign.sound_settings != expected_settings
        campaign.assign_attributes(settings.to_h.slice("musical_genre", "vocal_gender", "style", "music_notes"))
        return failure_result(:invalid_sound_settings) unless campaign.valid?
        campaign.save!
        campaign.sync_briefing!
        success_result(campaign)
      end
    end
  end
end
