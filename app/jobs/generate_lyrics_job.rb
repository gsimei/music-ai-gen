# frozen_string_literal: true

class GenerateLyricsJob < ApplicationJob
  queue_as :ai

  def perform(order_id)
    Rails.logger.info "[GenerateLyricsJob] STUB — generating lyrics for Order ##{order_id}"
    # Implementação real virá na Seção 9 (LyricsGenerator + Claude integration)
  end
end
