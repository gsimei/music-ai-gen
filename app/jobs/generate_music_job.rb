# frozen_string_literal: true

class GenerateMusicJob < ApplicationJob
  queue_as :ai

  def perform(order_id, melody_hint: nil)
    order = Order.find(order_id)
    if order.campaign
      if order.lyrics_approved?
        result = Campaigns::MusicRounds.call(order: order, feedback: melody_hint)
        if result.failure?
          order.with_lock { order.update!(status: "music_failed") if order.lyrics_approved? }
          Rails.logger.warn "[Campaign music #{order.id}] #{result.errors}"
          OrderChatBroadcaster.call(order)
        end
      end
      return
    end

    unless order.music_generating?
      begin
        order.start_music_generation!
      rescue AASM::InvalidTransition => e
        Rails.logger.warn "[GenerateMusicJob] Invalid transition for Order##{order_id}: #{e.message}"
        return
      end
    end

    OrderChatBroadcaster.call(order)
    result = MusicGenerator::Generator.call(order: order, melody_hint: melody_hint)

    unless result.success?
      Rails.logger.error "[GenerateMusicJob] Generator failed for Order##{order_id}: #{result.errors.inspect}"
      begin
        order.fail_music!
        OrderChatBroadcaster.call(order)
      rescue AASM::InvalidTransition => e
        Rails.logger.warn "[GenerateMusicJob] Could not transition to music_failed for Order##{order_id}: #{e.message}"
      end
    end
  end
end
