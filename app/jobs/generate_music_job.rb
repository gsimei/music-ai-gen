# frozen_string_literal: true

# Enqueued after lyrics approval.  Calls start_music_generation! on the order
# and drives the Mureka API pipeline.  Implementation in ROADMAP Section 11.
class GenerateMusicJob < ApplicationJob
  queue_as :ai

  def perform(order_id)
    order = Order.find(order_id)
    order.start_music_generation!
    # Mureka integration — ROADMAP Section 11
  end
end
