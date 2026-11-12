# frozen_string_literal: true

# Processes a single StripeEvent by dispatching to the appropriate handler.
#
# Idempotency: returns early if event is already processed.
# Retry: raises on handler failure so Solid Queue retries with backoff.
# Unrecognised event_type: raises to surface routing bugs.
class StripeWebhookProcessorJob < ApplicationJob
  queue_as :webhooks

  retry_on StandardError, wait: :polynomially_longer, attempts: 5 do |job, error|
    event = StripeEvent.find_by(id: job.arguments.first)
    event&.with_lock { event.update!(status: "failed") unless event.processed? }
    Rails.logger.error "[StripeWebhookProcessorJob] retries exhausted event=#{job.arguments.first} error=#{error.class}"
    Sentry.capture_exception(error)
  end

  discard_on ActiveRecord::RecordNotFound

  discard_on ActiveJob::DeserializationError do |job, error|
    Rails.logger.error "[StripeWebhookProcessorJob] DeserializationError — discarding: #{error.message}"
  end

  HANDLER_MAP = {
    "checkout.session.completed"    => ::Stripe::Handlers::CheckoutSessionCompleted,
    "payment_intent.payment_failed" => ::Stripe::Handlers::PaymentIntentFailed,
    "charge.refunded"               => ::Stripe::Handlers::ChargeRefunded
  }.freeze

  def perform(stripe_event_id)
    stripe_event = StripeEvent.find(stripe_event_id)

    return if stripe_event.processed?

    stripe_event.increment!(:attempt_count)

    stripe_event.with_lock do
      return if stripe_event.processed?

      handler_class = HANDLER_MAP[stripe_event.event_type]
      raise "No handler for event type: #{stripe_event.event_type}" unless handler_class

      result = handler_class.call(stripe_event: stripe_event)

      if result.success?
        stripe_event.update!(status: "processed", processed_at: Time.current)
      else
        raise "Handler failed: #{Array(result.errors).join(', ')}"
      end
    end
  end
end
