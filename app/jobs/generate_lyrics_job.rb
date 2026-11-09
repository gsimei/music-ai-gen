# frozen_string_literal: true

class GenerateLyricsJob < ApplicationJob
  queue_as :ai

  def perform(order_id, mode: "initial", parent_draft_id: nil, user_feedback: nil)
    order = Order.find(order_id)

    if mode == "initial"
      order.with_lock do
        return unless order.paid?
        order.start_lyrics_generation!
      end
      OrderChatBroadcaster.call(order)

      result = LyricsGenerator::Generator.call(
        order: order,
        mode:  :initial
      )

      raise "LyricsGenerator failed: #{result.errors}" if result.failure?

      order.lyrics_drafted!

      order.reload
      draft = order.current_draft

      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_lyrics",
        target:  "lyrics_section",
        partial: "orders/lyrics_section",
        locals:  { order: order, draft: draft, brand: order.brand }
      )

      OrderChatBroadcaster.call(order)

    elsif mode == "regen"
      result = LyricsGenerator::Generator.call(
        order:           order,
        mode:            :regen,
        parent_draft_id: parent_draft_id,
        user_feedback:   user_feedback
      )

      raise "LyricsGenerator failed: #{result.errors}" if result.failure?

      order.reload
      draft = order.lyrics_drafts.order(version: :desc).first

      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_lyrics",
        target:  "lyrics_content",
        partial: "lyrics/lyrics_content",
        locals:  { order: order, draft: draft }
      )

      OrderChatBroadcaster.call(order)
    end
  rescue StandardError
    if order
      order.fail_lyrics! if order.lyrics_drafting?
      OrderChatBroadcaster.call(order)
    end
    raise
  end
end
