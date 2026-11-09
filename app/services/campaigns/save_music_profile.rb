module Campaigns
  class SaveMusicProfile < BaseService
    attribute :campaign

    def call
      order = campaign.order
      user = order.user
      return failure_result(:invalid_state) unless user
      # Approval can select an older favorite. Persist that version's sound,
      # rather than the last settings the merchant happened to experiment with.
      settings = if order.approved?
        order.approved_music_generation&.request_payload&.dig("sound_settings")
      else
        campaign.sound_settings
      end
      return failure_result(:missing_direction) unless settings
      profile = nil
      user.with_lock do
        profile = user.business_music_profiles.find_or_initialize_by(business_key: BusinessMusicProfile.key_for(campaign.business_name))
        profile.assign_attributes(settings.slice("musical_genre", "vocal_gender", "style", "music_notes").merge("business_name" => campaign.business_name))
        return failure_result(:invalid_settings) unless profile.save
      end
      success_result(profile)
    end
  end
end
