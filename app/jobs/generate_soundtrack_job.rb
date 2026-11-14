# frozen_string_literal: true

class GenerateSoundtrackJob < ApplicationJob
  queue_as :ai

  def perform(order_id, input_id = nil)
    order = Order.find(order_id)
    order.with_lock do
      return unless (order.paid? || order.music_generating?) && order.soundtrack_enabled?
      input = order.soundtrack_input
      return unless input&.ready? && (input_id.nil? || input.id == input_id)
      order.start_soundtrack_generation! if order.paid?
    end

    result = MusicGenerator::Generator.call(order: order)
    return if result.failure? && result.errors == :busy

    unless result.success?
      Rails.logger.error "[GenerateSoundtrackJob] Generator failed for Order##{order_id}: #{result.errors.inspect}"
      order.fail_music! rescue AASM::InvalidTransition
    end
  rescue AASM::InvalidTransition => e
    Rails.logger.warn "[GenerateSoundtrackJob] Transition failed for Order##{order_id}: #{e.message}"
  end
end
