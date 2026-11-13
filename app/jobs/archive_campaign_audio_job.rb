require "tempfile"

class ArchiveCampaignAudioJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(asset_id)
    asset = OrderAsset.find(asset_id)
    return if !asset.order.campaign || !asset.music_variant?
    if archived?(asset)
      PrepareCampaignAudioJob.perform_later(asset.id) unless asset.audition_ready?
      PrepareFullAuditionJob.perform_later(asset.id) unless asset.full_audition_ready?
      return
    end
    Tempfile.create([ "jingle-version-", ".mp3" ]) do |file|
      Campaigns::AudioDownload.call(asset.provider_url.presence || asset.url, file.path)
      # Active Storage uploads in after_commit. Keep the IO open until the
      # enclosing lock transaction has committed, not just until attach returns.
      File.open(file.path) do |audio|
        asset.with_lock do
          return if archived?(asset)
          asset.audio.attach(io: audio, filename: "#{asset.order.reference}-#{asset.music_generation.iteration}-#{asset.variant_index}.mp3", content_type: "audio/mpeg", metadata: { private_order_audio: true })
        end
      end
    end
    PrepareCampaignAudioJob.perform_later(asset.id) unless asset.audition_ready?
    PrepareFullAuditionJob.perform_later(asset.id) unless asset.full_audition_ready?
  rescue StandardError
    asset&.update!(campaign_preview_status: "failed") unless asset&.campaign_preview_ready?
    OrderChatBroadcaster.call(asset.order) if asset
    raise
  end

  private

  def archived?(asset)
    asset.audio.attached? && asset.audio.blob.service.exist?(asset.audio.blob.key)
  end
end
