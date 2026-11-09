class GenerateCampaignMusicJob < ApplicationJob
  queue_as :ai
  RATE_LIMIT_RETRIES = 3

  def perform(generation_id)
    generation = MusicGeneration.find(generation_id)
    order = generation.order
    claimed = false
    order.with_lock do
      generation.reload
      return unless generation.pending?
      return if generation.next_poll_at && generation.next_poll_at > Time.current
      return unless order.music_generating?
      if order.music_generations.sum(:submission_attempts) >= Campaigns::MusicRounds::MAX_REQUESTS
        Campaigns::MusicFailure.call(generation, "technical_limit_reached")
        return
      end
      # Claim before calling the provider. A lost response must never cause an automatic POST retry.
      generation.update!(status: "processing", submitted_at: Time.current, next_poll_at: nil,
        submission_attempts: generation.submission_attempts + 1, error_code: nil)
      claimed = true
      cost = GenerationCost.find_by(music_generation: generation, operation: "music")
      if cost
        cost.update!(estimated_usd: GenerationCost.song_price(generation.model) * 2,
          estimated_brl: GenerationCost.song_price(generation.model) * 2 * cost.usd_brl, status: "uncertain",
          usage: cost.usage.merge("submission_attempts" => generation.submission_attempts))
      else
        GenerationCost.record!(order: order, music_generation: generation, operation: "music", provider: "mureka",
          model: generation.model, usd: GenerationCost.song_price(generation.model) * 2,
          usage: { requested_songs: 2, submission_attempts: generation.submission_attempts }, status: "uncertain")
      end
    end
    payload = generation.request_payload
    result = MusicGenerator::MurekaClient.call(model: payload.fetch("model"), n: 2,
      prompt: payload.fetch("prompt"), lyrics: payload.fetch("lyrics"), gender: payload["gender"])
    cost = GenerationCost.find_by!(music_generation: generation, operation: "music")
    unless result.success?
      details = result.value.is_a?(Hash) ? result.value : {}
      kind = details[:failure_kind] || "submission_uncertain"
      cost.update!(usage: cost.usage.merge("last_http_status" => details[:http_status], "failure_kind" => kind, "trace_id" => details[:trace_id]))
      if %w[rate_limited quota_exhausted request_rejected].include?(kind)
        # Explicit HTTP rejections have no accepted generation task.
        cost.update!(estimated_usd: 0, estimated_brl: 0, status: "estimated")
      end
      if kind == "rate_limited" && generation.submission_attempts < RATE_LIMIT_RETRIES
        retry_at = Time.current + (details[:retry_after] || 60 * generation.submission_attempts).seconds
        generation.update!(status: "pending", error_code: "rate_limited", next_poll_at: retry_at)
        self.class.set(wait_until: retry_at).perform_later(generation.id)
        OrderChatBroadcaster.call(order)
      else
        Campaigns::MusicFailure.call(generation, kind)
      end
      return
    end
    generation.update!(mureka_job_id: result.value.fetch(:job_id), next_poll_at: Time.current, error_code: nil)
    cost.update!(provider_request_id: generation.mureka_job_id)
    PollCampaignMusicJob.perform_later(generation.id)
    OrderChatBroadcaster.call(order)
  rescue StandardError
    # Once the task ID is saved, recovery only polls it. Never resubmit the song.
    if claimed && generation && generation.reload.mureka_job_id.blank?
      Campaigns::MusicFailure.call(generation, "submission_uncertain")
    end
    raise
  end
end
