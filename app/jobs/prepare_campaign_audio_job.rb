require "tmpdir"

class PrepareCampaignAudioJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(asset_id, revision = nil)
    asset = OrderAsset.find(asset_id)
    return unless asset.order.campaign && asset.music_variant?
    revision ||= asset.preview_revision
    return unless asset.preview_revision == revision
    return if asset.audition_ready?
    # The chosen clean excerpt is immutable. Other versions can still finish
    # preparation after approval so the comparison history remains playable.
    return if asset.approved_for_delivery? && !asset.campaign_preview_ready?
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Dir.mktmpdir("campaign-audio-") do |dir|
      destination = File.join(dir, "preview.m4a")
      audition_path = File.join(dir, "audition.m4a")
      existing_blob = asset.campaign_audio.blob if asset.campaign_preview_ready?
      metadata = if existing_blob
        existing_blob.open { |source| FileUtils.cp(source.path, destination) }
        existing_blob.metadata
      else
        asset.audio.blob.open do |source|
          Campaigns::AudioPreview.render(source: source.path, destination: destination, lyrics_sync: asset.lyrics_sync,
            start_seconds: asset.excerpt_start_seconds, duration_seconds: asset.excerpt_duration_seconds)
        end
      end
      Campaigns::AudioAudition.render(source: destination, destination: audition_path,
        start_seconds: metadata.fetch("start_seconds"), duration_seconds: metadata.fetch("duration_seconds"), seed: asset.id.to_s)
      File.open(destination) do |audio|
        File.open(audition_path) do |audition|
          asset.order.with_lock do
            asset.with_lock do
              return if asset.preview_revision != revision || asset.audition_ready?
              if existing_blob
                return unless asset.campaign_preview_ready? && asset.campaign_audio.blob.id == existing_blob.id
              else
                return if asset.approved_for_delivery?
                asset.campaign_audio.attach(io: audio, filename: "#{asset.order.reference}-trecho-#{asset.id}-#{revision}.m4a",
                  content_type: "audio/mp4", metadata: metadata.merge("source_blob_id" => asset.audio.blob.id,
                    "preview_revision" => revision, "private_order_audio" => true))
              end
              asset.audition_audio.attach(io: audition, filename: "previa-#{asset.id}-#{revision}.m4a", content_type: "audio/mp4",
                metadata: { private_order_audio: true, source_blob_id: asset.campaign_audio.blob.id,
                  preview_revision: revision, watermark_version: Campaigns::AudioAudition::VERSION })
              asset.update!(campaign_preview_status: "ready")
            end
          end
        end
      end
    end
    OrderChatBroadcaster.call(asset.order)
  rescue StandardError => error
    asset&.with_lock do
      asset.update!(campaign_preview_status: "failed") if asset.preview_revision == revision && !asset.campaign_preview_ready? && !asset.approved_for_delivery?
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
