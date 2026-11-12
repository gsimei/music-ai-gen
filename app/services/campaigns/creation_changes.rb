module Campaigns
  # Save the visible form and use exactly that draft/settings for the next request.
  # A rejected request rolls back all edits rather than silently saving half a form.
  class CreationChanges < BaseService
    attribute :order
    attribute :draft_id
    attribute :content, :string
    attribute :settings
    attribute :intent, :string
    attribute :feedback, :string
    attribute :lyrics_feedback, :string

    def call
      result = failure_result(:invalid_state)
      order.with_lock do
        return result unless order.campaign && order.lyrics_editable? && %w[save rewrite generate].include?(intent)
        return failure_result(:regen_limit_reached) if order.completed_music_rounds >= MusicRounds::LIMIT
        # The savepoint also protects callers already inside a transaction.
        Order.transaction(requires_new: true) do
          result = LyricsEditor.call(order: order, draft_id: draft_id, content: content)
          raise ActiveRecord::Rollback if result.failure?
          result = SoundSettings.call(order: order, settings: settings)
          raise ActiveRecord::Rollback if result.failure?
          if order.campaign.selected_music_asset_id?
            order.campaign.update!(selected_music_asset: nil, video_revision: order.campaign.video_revision + 1)
          end
          result = case intent
          when "rewrite"
            Orders::LyricsRegenerator.call(order: order, user_feedback: lyrics_feedback)
          when "generate"
            if order.lyrics_ready?
              Orders::LyricsApprover.call(order: order, draft_id: order.current_draft.id)
            else
              MusicRounds.call(order: order, feedback: feedback)
            end
          else
            success_result(order.current_draft)
          end
          raise ActiveRecord::Rollback if result.failure?
        end
      end
      result
    end
  end
end
