# frozen_string_literal: true

module ::Stripe
  # Validates and dispatches incoming Stripe webhook events.
  #
  # Responsibilities:
  # - Verifies HMAC-SHA256 signature before any DB write
  # - Idempotency gate: already-processed events return early
  # - Unknown event types are stored as skipped, no job enqueued
  # - Handled events create a pending StripeEvent and enqueue the processor job
  class WebhookHandler < BaseService
    HANDLED_EVENTS = %w[
      checkout.session.completed
      payment_intent.payment_failed
      charge.refunded
    ].freeze

    attribute :payload,          :string
    attribute :signature_header, :string

    def call
      event = verify_signature!
      return failure_result("invalid_signature") unless event

      # Idempotency: already handled
      existing = StripeEvent.find_by(stripe_event_id: event.id)
      if existing&.processed? || existing&.skipped?
        return success_result(:already_processed)
      end

      if HANDLED_EVENTS.include?(event.type)
        stripe_event = find_or_initialize_event(event)
        stripe_event.update!(
          status:     "pending",
          event_type: event.type,
          payload:    event.as_json
        )
        StripeWebhookProcessorJob.perform_later(stripe_event.id)
        success_result(:enqueued)
      else
        stripe_event = find_or_initialize_event(event)
        stripe_event.update!(
          status:     "skipped",
          event_type: event.type,
          payload:    event.as_json
        )
        success_result(:skipped)
      end
    rescue ::Stripe::SignatureVerificationError => e
      Rails.logger.warn "[WebhookHandler] Invalid signature: #{e.message}"
      failure_result("invalid_signature")
    end

    private

    def verify_signature!
      ::Stripe::Webhook.construct_event(
        payload,
        signature_header,
        ENV.fetch("STRIPE_WEBHOOK_SECRET", "")
      )
    rescue ::Stripe::SignatureVerificationError
      nil
    end

    def find_or_initialize_event(event)
      StripeEvent.find_or_initialize_by(stripe_event_id: event.id)
    end
  end
end
