module Campaigns
  # One validated path for conversational changes and the visible sound controls.
  class ChatDirection < BaseService
    attribute :order
    attribute :parsed
    attribute :expected_settings

    GENRE_ALIASES = { "country" => "sertanejo", "folk" => "acustico", "electronic" => "eletronico", "forró" => "forro", "axé" => "axe" }.freeze
    MOODS = { "happy" => "animado", "energetic" => "marcante", "calm" => "acolhedor" }.freeze

    def call
      changes = parsed["sound_settings"]
      if changes.nil? # Compatibility with older chat responses.
        brief = parsed["briefing"].is_a?(Hash) ? parsed["briefing"] : {}
        changes = {}
        if brief["music_style"].present?
          changes["musical_genre"] = GENRE_ALIASES.fetch(brief["music_style"], brief["music_style"])
        end
        changes["style"] = MOODS[brief["mood"]] if MOODS.key?(brief["mood"])
        changes["vocal_gender"] = brief["vocal_gender"] || brief["gender"] if brief["vocal_gender"] || brief["gender"]
      end
      return failure_result(:invalid_sound_settings) unless changes.is_a?(Hash)
      changes = changes.slice("musical_genre", "vocal_gender", "style", "music_notes").compact
      return success_result(nil) if changes.empty?
      current = order.campaign.reload.sound_settings
      return failure_result(:stale_sound_settings) if current != expected_settings
      return success_result(nil) if current.merge(changes) == current
      SoundSettings.call(order: order, settings: changes, expected_settings: expected_settings)
    end
  end
end
