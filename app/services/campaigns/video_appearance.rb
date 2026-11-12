module Campaigns
  class VideoAppearance < BaseService
    attribute :order
    attribute :revision
    attribute :settings

    def call
      order.with_lock do
        return failure_result(:invalid_state) unless order.campaign && %w[preview_ready music_failed].include?(order.status) && order.lyrics_revision_token.blank?
        campaign = order.campaign
        return failure_result(:stale_video) unless Integer(revision.to_s, exception: false) == campaign.video_revision
        return failure_result(:invalid_appearance) unless settings.is_a?(Hash)

        appearance = settings.stringify_keys.slice("business_name", "logo", "remove_logo", "show_cta", "cta_color", "call_to_action", "contact")
        appearance.delete("logo") if appearance["logo"].blank?
        return failure_result(:invalid_logo) if appearance["logo"] && !appearance["logo"].is_a?(ActionDispatch::Http::UploadedFile)
        campaign.assign_attributes(appearance)
        return failure_result(:invalid_appearance) unless campaign.valid?
        return success_result(campaign) unless campaign.changed? || campaign.attachment_changes.any?

        campaign.video_revision += 1
        campaign.save!
        success_result(campaign)
      end
    end
  end
end
