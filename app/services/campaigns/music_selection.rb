module Campaigns
  # Choosing a track opens video setup. Approval and rendering happen separately.
  class MusicSelection < BaseService
    attribute :order
    attribute :asset_id
    attribute :clear, :boolean, default: false

    def call
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && %w[preview_ready music_failed].include?(order.status) && order.lyrics_revision_token.blank?
        asset = order.all_music_assets.find_by(id: asset_id) unless clear
        return failure_result(:not_found) unless clear || asset
        return failure_result(:preview_not_ready) unless clear || asset.audition_ready?
        campaign = order.campaign
        if campaign.selected_music_asset_id != asset&.id
          campaign.update!(selected_music_asset: asset, video_revision: campaign.video_revision + 1)
        end
        success_result(asset)
      end
    end
  end
end
