# Recover durable state left behind when a worker is killed. Charged AI calls
# are never resubmitted automatically once they have started.
class RecoverInterruptedCampaignJobsJob < ApplicationJob
  queue_as :critical
  STALE_AFTER = 30.minutes

  def perform
    cutoff = STALE_AFTER.ago
    Order.joins(:campaign).where(status: %w[paid lyrics_drafting lyrics_approved]).where("orders.updated_at < ?", cutoff).find_each do |order|
      order.with_lock do
        next unless order.updated_at < cutoff
        if order.paid?
          GenerateLyricsJob.perform_later(order.id)
          order.touch
        elsif order.lyrics_approved? && !order.music_generations.where(status: %w[pending processing]).exists?
          GenerateMusicJob.perform_later(order.id)
          order.touch
        elsif order.lyrics_drafting?
          order.current_draft ? order.lyrics_drafted! : order.fail_lyrics!
        end
      end
      OrderChatBroadcaster.call(order)
    end

    # A completed pair can outlive the worker that archives/prepares its audio.
    # These jobs download existing tracks and render locally; no AI POST occurs.
    OrderAsset.joins(:music_generation, order: :campaign)
      .where(kind: "music_variant", campaign_preview_status: "queued", music_generations: { status: "completed" })
      .where("order_assets.updated_at < ?", cutoff).find_each do |asset|
      asset.with_lock do
        next unless asset.campaign_preview_status == "queued" && asset.updated_at < cutoff && !asset.audition_ready?
        ArchiveCampaignAudioJob.perform_later(asset.id)
        asset.touch
      end
    end

    Order.joins(:campaign).where.not(lyrics_revision_token: nil).where("orders.updated_at < ?", cutoff).find_each do |order|
      order.with_lock do
        next unless order.lyrics_revision_token.present? && order.updated_at < cutoff
        order.update!(lyrics_revision_token: nil,
          lyrics_revision_error: "A reescrita foi interrompida. Sua última letra está salva. Tente novamente.")
      end
      OrderChatBroadcaster.call(order)
    end

    Campaign.joins(:order).where(orders: { status: "approved" }, video_status: %w[pending queued rendering])
      .where("campaigns.updated_at < ?", cutoff).find_each do |campaign|
      campaign.with_lock do
        next unless campaign.updated_at < cutoff && campaign.order.approved?
        if campaign.video_status == "pending"
          campaign.queue_video!
        elsif %w[queued rendering].include?(campaign.video_status)
          uploaded = campaign.video.attached? && campaign.video.blob.service.exist?(campaign.video.blob.key)
          campaign.update!(video_status: uploaded ? "ready" : "failed",
            video_error: uploaded ? nil : "A montagem foi interrompida. Sua música está salva. Tente montar o vídeo novamente.")
        end
      end
    end
  end
end
