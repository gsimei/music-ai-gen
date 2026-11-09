class RewriteCampaignLyricsJob < ApplicationJob
  queue_as :ai

  def perform(order_id, token, parent_draft_id, feedback)
    order = Order.find(order_id)
    # Claim the request once. Duplicate deliveries cannot make another paid call.
    order.with_lock do
      return unless order.lyrics_revision_token == token
      order.update!(lyrics_revision_token: "running:#{token}")
    end
    result = LyricsGenerator::Generator.call(order: order, mode: :regen,
      parent_draft_id: parent_draft_id, user_feedback: feedback)
    order.update!(lyrics_revision_token: nil, lyrics_revision_error: result.success? ? nil : "Não conseguimos reescrever. Sua letra anterior está salva. Tente novamente.")
    OrderChatBroadcaster.call(order)
  rescue StandardError
    order&.update!(lyrics_revision_token: nil, lyrics_revision_error: "Não conseguimos reescrever. Sua letra anterior está salva. Tente novamente.")
    OrderChatBroadcaster.call(order) if order
    raise
  end
end
