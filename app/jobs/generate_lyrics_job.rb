# frozen_string_literal: true

class GenerateLyricsJob < ApplicationJob
  queue_as :ai

  def perform(order_id, mode: "initial", parent_draft_id: nil, user_feedback: nil)
    order = Order.find(order_id)

    if mode == "initial"
      order.start_lyrics_generation!

      result = LyricsGenerator::Generator.call(
        order: order,
        mode:  :initial
      )

      raise "LyricsGenerator failed: #{result.errors}" if result.failure?

      order.lyrics_drafted!

    elsif mode == "regen"
      result = LyricsGenerator::Generator.call(
        order:           order,
        mode:            :regen,
        parent_draft_id: parent_draft_id,
        user_feedback:   user_feedback
      )

      raise "LyricsGenerator failed: #{result.errors}" if result.failure?

      # Broadcast the updated lyrics content to the page so the customer sees
      # the new draft without reloading.
      order.reload
      draft = order.lyrics_drafts.order(version: :desc).first
      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_lyrics",
        target:  "lyrics_content",
        partial: "lyrics/lyrics_content",
        locals:  { order: order, draft: draft }
      )
    end
  end
end
