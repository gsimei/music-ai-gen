require "tmpdir"

class PrepareCampaignAudioJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(asset_id, revision = nil)
    asset = OrderAsset.find(asset_id)
    return unless asset.order.campaign && asset.music_variant?
    return if asset.order.approved?
    revision ||= asset.preview_revision
    return unless asset.preview_revision == revision
    return if asset.campaign_preview_ready?
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Dir.mktmpdir("campaign-audio-") do |dir|
      destination = File.join(dir, "preview.m4a")
      metadata = asset.audio.blob.open do |source|
        Campaigns::AudioPreview.render(source: source.path, destination: destination, lyrics_sync: asset.lyrics_sync, start_seconds: asset.excerpt_start_seconds)
      end
      File.open(destination) do |audio|
        asset.order.with_lock do
          asset.with_lock do
            return if asset.order.approved? || asset.preview_revision != revision || asset.campaign_preview_ready?
            asset.campaign_audio.attach(io: audio, filename: "#{asset.order.reference}-trecho-#{asset.id}-#{revision}.m4a",
              content_type: "audio/mp4", metadata: metadata.merge("source_blob_id" => asset.audio.blob.id, "preview_revision" => revision))
            asset.update!(campaign_preview_status: "ready")
          end
        end
      end
    end
    OrderChatBroadcaster.call(asset.order)
  rescue StandardError => error
    asset&.with_lock do
      asset.update!(campaign_preview_status: "failed") if asset.preview_revision == revision && !asset.campaign_preview_ready? && !asset.order.approved?
    end
    OrderChatBroadcaster.call(asset.order) if asset
    raise
  ensure
    if started_at
      GenerationCost.record!(order: asset.order, operation: "audio_preview", provider: "local", model: "ffmpeg",
        usage: { asset_id: asset.id, wall_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3),
          outcome: asset.campaign_preview_status, bytes: asset.campaign_audio.attached? ? asset.campaign_audio.blob.byte_size : 0 })
    end
  end
end
