# frozen_string_literal: true

# Processes a single StripeEvent by dispatching to the appropriate handler.
#
# Idempotency: returns early if event is already processed.
# Retry: raises on handler failure so Solid Queue retries with backoff.
# Unrecognised event_type: raises to surface routing bugs.
class StripeWebhookProcessorJob < ApplicationJob
  queue_as :webhooks

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
