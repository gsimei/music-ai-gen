class RenderCampaignVideoJob < ApplicationJob
  queue_as :default

  def perform(campaign_id)
    campaign = Campaign.find(campaign_id)
    campaign.with_lock do
      return unless campaign.video_status == "queued" && campaign.order.approved?
      campaign.update!(video_status: "rendering")
    end
    broadcast(campaign)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Campaigns::VideoRenderer.new(campaign).call
    campaign.update!(video_status: "ready", video_error: nil)
    broadcast(campaign)
  rescue StandardError => error
    Rails.logger.error("[Campaign video #{campaign_id}] #{error.class}: #{error.message}")
    Sentry.capture_exception(error, tags: { campaign_id: campaign_id })
    campaign&.update!(video_status: "failed", video_error: "Não conseguimos montar o vídeo. Sua música está salva. Tente novamente.")
    broadcast(campaign) if campaign
  ensure
    if started_at
      GenerationCost.record!(order: campaign.order, operation: "video_render", provider: "local", model: "ffmpeg",
        usage: { wall_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3),
          outcome: campaign.video_status, bytes: campaign.video.attached? ? campaign.video.blob.byte_size : 0 })
    end
  end

  private

  def broadcast(campaign)
    Turbo::StreamsChannel.broadcast_replace_to("campaign_#{campaign.id}", target: "campaign-delivery",
      partial: "campaigns/delivery", locals: { campaign: campaign })
  end
end
