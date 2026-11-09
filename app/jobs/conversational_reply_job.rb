# frozen_string_literal: true

class ConversationalReplyJob < ApplicationJob
  queue_as :default

  def perform(order_id, message)
    order = Order.find(order_id)

    result = ConversationalBriefingService.call(
      order:       order,
      new_message: message
    )

    if result.failure?
      Turbo::StreamsChannel.broadcast_replace_to(
        "order_#{order.id}_chat",
        target:  "chat-typing-indicator",
        partial: "order_chat/message",
        locals:  { role: "assistant", content: I18n.t("order_chat.error_message") }
      )
      return
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      "order_#{order.id}_chat",
      target:  "chat-typing-indicator",
      partial: "order_chat/message",
      locals:  { role: "assistant", content: result.value[:reply] }
    )

    Turbo::StreamsChannel.broadcast_update_to(
      "order_#{order.id}_chat",
      target:  "chat-suggestions",
      partial: "order_chat/suggestions",
      locals:  { suggestions: Array(result.value[:suggestions]) }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      "order_#{order.id}_chat",
      target:  "chat-scroll-anchor",
      partial: "order_chat/scroll_anchor"
    )

    instrumental = order.briefing&.extra_params&.dig("instrumental")

    order.reload
    if order.campaign && (order.preview_ready? || order.music_failed?)
      feedback = result.value[:revision_feedback].presence || (order.briefing_messages.where(role: "user").last(5).map(&:content) + [message]).uniq.join("\n")
      revision = if result.value[:ready] == true && result.value[:revision_target] == "lyrics"
        Orders::LyricsRegenerator.call(order: order, user_feedback: feedback)
      elsif result.value[:generate_music] == true && result.value[:revision_target] == "music"
        Campaigns::MusicRounds.call(order: order, feedback: feedback.first(400), retry_failed: order.music_failed?)
      end
      if revision&.failure?
        Turbo::StreamsChannel.broadcast_append_to("order_#{order.id}_chat", target: "chat-transcript", partial: "order_chat/message",
          locals: { role: "assistant", content: "Não foi iniciada uma nova geração. Confira as rodadas disponíveis em Letra e música; suas versões anteriores continuam salvas." })
      end
      OrderChatBroadcaster.call(order)
      return
    end

    OrderChatBroadcaster.call(order) if order.campaign

    pre_music = order.paid? || order.lyrics_drafting? || order.lyrics_ready?

    if instrumental && (result.value[:ready] || result.value[:generate_music]) && pre_music
      # Instrumental shortcut — works from any pre-music state
      generate_instrumental_music(order)
      Turbo::StreamsChannel.broadcast_update_to(
        "order_#{order.id}_chat",
        target: "chat-suggestions",
        html:   ""
      )
    elsif result.value[:ready] && order.paid?
      GenerateLyricsJob.perform_later(order.id)
      Turbo::StreamsChannel.broadcast_update_to(
        "order_#{order.id}_chat",
        target: "chat-suggestions",
        html:   ""
      )
    elsif result.value[:ready] && order.lyrics_ready?
      feedback = result.value[:revision_feedback].presence || (order.briefing_messages.where(role: "user").last(5).map(&:content) + [message]).uniq.join("\n")
      Orders::LyricsRegenerator.call(order: order, user_feedback: feedback)
      OrderChatBroadcaster.call(order)
    elsif result.value[:generate_music] && !result.value[:ready]
      draft = order.current_draft
      if draft
        Orders::LyricsApprover.call(order: order, draft_id: draft.id)
        OrderChatBroadcaster.call(order)
        Turbo::StreamsChannel.broadcast_update_to(
          "order_#{order.id}_chat",
          target: "chat-suggestions",
          html:   ""
        )
      end
    end
  end

  private

  def generate_instrumental_music(order)
    draft = LyricsDraft.create!(
      order:   order,
      content: "[instrumental]",
      source:  "ai_generated",
      version: (order.lyrics_drafts.maximum(:version) || 0) + 1
    )
    order.current_lyrics_draft_id = draft.id

    order.start_lyrics_generation! if order.paid?
    order.lyrics_drafted!           if order.lyrics_drafting?
    order.approve_lyrics!           if order.lyrics_ready?
  rescue AASM::InvalidTransition => e
    Rails.logger.warn "[ConversationalReplyJob] Instrumental transition failed (status=#{order.status}): #{e.message}"
  end
end
