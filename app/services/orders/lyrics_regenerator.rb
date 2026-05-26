# frozen_string_literal: true

module Orders
  # Validates eligibility for lyrics regeneration and enqueues GenerateLyricsJob
  # in "regen" mode with the current draft as the parent.
  #
  # Guards enforced before enqueuing:
  #   - Order must be in lyrics_ready state
  #   - Order must not have exhausted its lyrics_regen_limit
  class LyricsRegenerator < BaseService
    attribute :order
    attribute :user_feedback, :string

    def call
      unless order.lyrics_ready?
        return failure_result(:invalid_state)
      end

      if order.lyrics_regen_used >= order.lyrics_regen_limit
        return failure_result(:regen_limit_reached)
      end

      parent_draft = order.lyrics_drafts.order(version: :desc).first

      GenerateLyricsJob.perform_later(
        order.id,
        mode:            "regen",
        parent_draft_id: parent_draft&.id,
        user_feedback:   user_feedback
      )

      success_result
    end
  end
end
