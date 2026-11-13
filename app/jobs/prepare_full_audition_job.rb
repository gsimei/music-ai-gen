require "tmpdir"

# Whole track with the sound watermark, for listening before approval. The
# clean recording stays behind approval (CampaignAudioController#final).
class PrepareFullAuditionJob < ApplicationJob
  queue_as :default
  # One render per asset at a time; extra enqueues (repeated clicks) are dropped, not queued.
  limits_concurrency to: 1, key: ->(asset_id) { "full_audition/#{asset_id}" }, duration: 15.minutes, on_conflict: :discard
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(asset_id)
    asset = OrderAsset.find(asset_id)
    return unless asset.order.campaign && asset.music_variant? && asset.audio.attached?
    return if asset.full_audition_ready?
    duration = asset.track_duration_seconds
    raise ArgumentError, "track duration unknown for asset #{asset.id}" unless duration.positive?
    source_blob = asset.audio.blob
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Dir.mktmpdir("campaign-full-audition-") do |dir|
      destination = File.join(dir, "full.m4a")
      source_blob.open do |source|
        Campaigns::AudioAudition.render(source: source.path, destination: destination, start_seconds: 0, duration_seconds: duration,
          seed: asset.id.to_s)
      end
      File.open(destination) do |audition|
        asset.with_lock do
          return if asset.full_audition_ready? || !asset.audio.attached? || asset.audio.blob.id != source_blob.id
          asset.full_audition_audio.attach(io: audition, filename: "previa-completa-#{asset.id}.m4a", content_type: "audio/mp4",
            metadata: { private_order_audio: true, source_blob_id: source_blob.id, watermark_version: Campaigns::AudioAudition::VERSION })
        end
      end
    end
    OrderChatBroadcaster.call(asset.order)
  ensure
    if started_at
      GenerationCost.record!(order: asset.order, operation: "full_audition", provider: "local", model: "ffmpeg",
        usage: { asset_id: asset.id, wall_seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3),
          outcome: asset.full_audition_ready? ? "ready" : "failed",
          bytes: asset.full_audition_audio.attached? ? asset.full_audition_audio.blob.byte_size : 0 })
    end
  end
end
