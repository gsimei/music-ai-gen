# frozen_string_literal: true

class DeliverOrderJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    Rails.logger.info "[DeliverOrderJob] STUB — delivering Order ##{order_id}"
    # Implementação real virá na Seção 14 (Delivery flow)
  end
end
