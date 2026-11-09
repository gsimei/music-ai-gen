class PollCampaignMusicJob < ApplicationJob
  queue_as :default
  MAX_WAIT = 30.minutes
  LEASE = 90.seconds

  def perform(generation_id)
    generation = MusicGeneration.find(generation_id)
    order = generation.order
    claimed = false
    order.with_lock do
      generation.reload
      return unless generation.processing? && generation.mureka_job_id.present?
      return if generation.poll_lease_until && generation.poll_lease_until > Time.current
      return if generation.next_poll_at && generation.next_poll_at > Time.current
      generation.update!(poll_lease_until: Time.current + LEASE)
      claimed = true
    end
    result = MusicGenerator::MurekaStatusClient.call(job_id: generation.mureka_job_id)
    order.with_lock do
      generation.reload
      return unless generation.processing?
      generation.increment!(:poll_count)
      if result.success? && result.value[:status] == "succeeded"
        choices = Array(result.value[:choices])
        cost = GenerationCost.find_by!(music_generation: generation, operation: "music")
        cost.update!(provider_request_id: generation.mureka_job_id, usage: cost.usage.merge("returned_songs" => choices.size))
        if choices.size != 2 || choices.any? { |choice| choice[:url].blank? }
          Campaigns::MusicFailure.call(generation, "incomplete_pair")
        else
          choices.each_with_index do |choice, index|
            generation.order_assets.create!(order: order, kind: "music_variant", variant_index: index,
              provider_url: choice[:url], flac_url: choice[:flac_url], wav_url: choice[:wav_url],
              duration_ms: choice[:duration_ms], lyrics_sync: { sections: choice[:lyrics_sections] || [] }, campaign_preview_status: "queued")
          end
          generation.update!(status: "completed", ready_at: Time.current, error_code: nil, poll_lease_until: nil, next_poll_at: nil)
          cost.update!(status: "estimated")
          order.update!(status: "preview_ready", music_regen_used: [order.completed_music_rounds - 1, 0].max) unless order.approved? || order.cancelled? || order.refunded?
          generation.order_assets.each { |asset| ArchiveCampaignAudioJob.perform_later(asset.id) }
        end
      elsif result.success? && result.value[:status] == "failed"
        Campaigns::MusicFailure.call(generation, "provider_failed")
      elsif (generation.submitted_at || generation.created_at) < MAX_WAIT.ago
        Campaigns::MusicFailure.call(generation, "generation_delayed")
      else
        # Transient query errors are not evidence that paid generation failed.
        wait = result.success? ? (generation.poll_count < 12 ? 5 : 15) : [15 * generation.poll_count, 60].min
        next_at = Time.current + wait.seconds
        generation.update!(poll_lease_until: nil, next_poll_at: next_at, error_code: result.success? ? nil : "status_unavailable")
        self.class.set(wait_until: next_at).perform_later(generation.id)
      end
    end
    OrderChatBroadcaster.call(order)
  rescue StandardError
    # The watchdog re-enqueues a lost query; this does not spend another generation.
    if claimed && generation&.reload&.processing?
      generation.update!(poll_lease_until: nil, next_poll_at: 30.seconds.from_now)
    end
    raise
  end
end
