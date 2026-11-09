# frozen_string_literal: true

# Keep the reloadable workflow and preview synchronized after async work.
class OrderChatBroadcaster
  def self.call(order)
    order.reload
    I18n.with_locale(order.locale) do
      draft = order.current_draft
      assets = order.music_variant_assets
      Turbo::StreamsChannel.broadcast_update_to(
        "order_#{order.id}_chat", target: "chat-workflow",
        partial: "order_chat/workflow", locals: { order: order, draft: draft }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_chat", target: "chat-lyrics-panel",
        partial: "order_chat/right_panel", locals: { order: order, draft: draft, assets: assets }
      )
      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_chat", target: "chat-scroll-anchor", partial: "order_chat/scroll_anchor"
      )
    end
  end
end
