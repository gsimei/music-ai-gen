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
    finish_revision(order, token, result.success? ? nil : "Não conseguimos reescrever. Sua letra anterior está salva. Tente novamente.")
    OrderChatBroadcaster.call(order)
  rescue StandardError
    finish_revision(order, token, "Não conseguimos reescrever. Sua letra anterior está salva. Tente novamente.") if order
    OrderChatBroadcaster.call(order) if order
    raise
  end

  private

  def finish_revision(order, token, error)
    order.with_lock do
      return unless order.lyrics_revision_token == "running:#{token}"
      order.update!(lyrics_revision_token: nil, lyrics_revision_error: error)
    end
  end
end
