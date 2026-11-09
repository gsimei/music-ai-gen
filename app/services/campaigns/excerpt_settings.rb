module Campaigns
  class ExcerptSettings < BaseService
    attribute :order
    attribute :asset_id
    attribute :start_seconds
    attribute :automatic, :boolean, default: false
    attribute :revision

    def call
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && %w[preview_ready music_failed].include?(order.status)
        asset = order.all_music_assets.find_by(id: asset_id)
        return failure_result(:not_found) unless asset
        asset.with_lock do
          return failure_result(:stale_preview) unless Integer(revision.to_s, exception: false) == asset.preview_revision
          return failure_result(:preview_busy) if asset.campaign_preview_status == "queued"
          return failure_result(:preview_not_ready) unless asset.audio.attached? && asset.campaign_audio.attached?
          start = automatic ? nil : Float(start_seconds.to_s, exception: false)
          return failure_result(:invalid_excerpt) unless automatic || (start&.finite? && start >= 0 && start <= asset.excerpt_max_start)
          start = start.round(2) if start
          return success_result(asset) if asset.campaign_preview_ready? && asset.excerpt_start_seconds == start
          asset.update!(excerpt_start_seconds: start, preview_revision: asset.preview_revision + 1, campaign_preview_status: "queued")
          PrepareCampaignAudioJob.perform_later(asset.id, asset.preview_revision)
          success_result(asset)
        end
      end
    end
  end
end
