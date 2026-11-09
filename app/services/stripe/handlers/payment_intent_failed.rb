# frozen_string_literal: true

module ::Stripe
  module Handlers
    # Handles payment_intent.payment_failed events.
    #
    # Late failure notifications must never undo a confirmed payment.
    class PaymentIntentFailed < BaseService
      attribute :stripe_event

      def call
        pi_obj = stripe_event.payload.dig("data", "object")
        pi_id  = pi_obj&.fetch("id", nil)

        order = find_order(pi_id, pi_obj)
        return success_result(:no_order_found) unless order

        order.with_lock do
          return success_result(:already_handled) unless order.pending? || order.payment_failed?
          return success_result(:already_handled) if order.paid_at.present? || order.payment_failed?

          order.update!(status: "payment_failed", stripe_payment_intent_id: pi_id)
          stripe_event.update!(order: order)
        end
        success_result(order)
      end

      private

      def find_order(pi_id, pi_obj)
        return nil if pi_id.blank?

        Order.find_by(stripe_payment_intent_id: pi_id) ||
          Order.find_by(reference: pi_obj&.dig("metadata", "reference"))
      end
    end
  end
end
