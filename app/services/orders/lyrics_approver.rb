# frozen_string_literal: true

module Orders
  # Approves a lyrics draft and fires the approve_lyrics! AASM event.
  #
  # Guards enforced before transitioning:
  #   - Order must be in lyrics_ready state
  #   - Draft must belong to the order
  #   - Draft must not already be locked or approved
  #
  # On success the AASM after callback lock_lyrics_and_start_music runs,
  # which marks the draft locked/approved, sets approved_lyrics_draft_id,
  # and enqueues music generation.
  class LyricsApprover < BaseService
    attribute :order
    attribute :draft_id

    def call
      unless order.lyrics_ready?
        return failure_result(:invalid_state)
      end

      draft = order.lyrics_drafts.find_by(id: draft_id)
      return failure_result(:draft_not_found) if draft.nil?

      if draft.is_locked || draft.is_approved
        return failure_result(:draft_already_locked)
      end

      ApplicationRecord.transaction do
        order.current_lyrics_draft_id = draft.id
        order.approve_lyrics!
      end

      success_result(order)
    rescue AASM::InvalidTransition => e
      Rails.logger.warn "[LyricsApprover] InvalidTransition for order ##{order.id}: #{e.message}"
      failure_result(:invalid_transition)
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[LyricsApprover] RecordInvalid for order ##{order.id}: #{e.message}"
      failure_result(e.message)
    end
  end
end
