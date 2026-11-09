module Campaigns
  class MusicFailure
    def self.call(generation, reason)
      generation.order.with_lock do
        generation.reload
        return if generation.completed? || generation.cancelled?
        generation.update!(status: "failed", error_code: reason, poll_lease_until: nil, next_poll_at: nil)
        generation.order.update!(status: "music_failed") if generation.order.music_generating?
      end
      OrderChatBroadcaster.call(generation.order)
    end
  end
end
