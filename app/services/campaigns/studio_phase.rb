module Campaigns
  # Único lugar que mapeia status do pedido + música escolhida + video_status para a fase do estúdio.
  module StudioPhase
    STEPS = { lyrics: 1, music: 2, video: 3, rendering: 3, failed_video: 3, delivered: 4 }.freeze

    def self.for(order)
      campaign = order.campaign
      return unless campaign

      case order.status
      when "paid", "lyrics_drafting", "lyrics_ready", "lyrics_failed" then :lyrics
      when "lyrics_approved", "music_generating" then :music
      when "preview_ready", "music_failed" then campaign.selected_music_asset ? :video : :music
      when "approved"
        case campaign.video_status
        when "pending", "queued", "rendering" then :rendering
        when "failed" then :failed_video
        when "ready" then :delivered
        end
      end
    end

    def self.step(phase) = STEPS[phase]
  end
end
