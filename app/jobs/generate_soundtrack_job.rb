# frozen_string_literal: true

class GenerateSoundtrackJob < ApplicationJob
  queue_as :ai

  def perform(order_id)
    order = Order.find(order_id)
    order.start_soundtrack_generation! if order.paid?

    result = MusicGenerator::Generator.call(order: order)

    unless result.success?
      Rails.logger.error "[GenerateSoundtrackJob] Generator failed for Order##{order_id}: #{result.errors.inspect}"
      order.fail_music! rescue AASM::InvalidTransition
    end
  rescue AASM::InvalidTransition => e
    Rails.logger.warn "[GenerateSoundtrackJob] Transition failed for Order##{order_id}: #{e.message}"
  end
end
