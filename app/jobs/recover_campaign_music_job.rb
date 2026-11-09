class RecoverCampaignMusicJob < ApplicationJob
  queue_as :default

  def perform(order_id = nil)
    scope = MusicGeneration.joins(order: :campaign).where(status: %w[pending processing])
    scope = scope.where(order_id: order_id) if order_id
    scope.where("music_generations.updated_at < ?", 30.seconds.ago).find_each do |generation|
      generation.order.with_lock do
        generation.reload
        next unless %w[pending processing].include?(generation.status)
        next if generation.next_poll_at && generation.next_poll_at > Time.current
        next if generation.poll_lease_until && generation.poll_lease_until > Time.current
        if generation.pending?
          GenerateCampaignMusicJob.perform_later(generation.id)
        elsif generation.mureka_job_id.present?
          PollCampaignMusicJob.perform_later(generation.id)
        elsif generation.submitted_at.nil? || generation.submitted_at < 3.minutes.ago
          Campaigns::MusicFailure.call(generation, "submission_uncertain")
        end
      end
    end
  end
end
