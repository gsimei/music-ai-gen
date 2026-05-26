# frozen_string_literal: true

module ::Stripe
  module Handlers
    # Handles payment_intent.payment_failed events.
    #
    # Uses update_columns (bypasses AASM) so the order can be marked
    # payment_failed from any state — Stripe may send this for orders
    # that are mid-processing.
    # Idempotent: returns :already_handled if order is already payment_failed.
    # Returns :no_order_found if no matching order exists — not an error.
    class PaymentIntentFailed < BaseService
      attribute :stripe_event

      def call
        pi_obj = stripe_event.payload.dig("data", "object")
        pi_id  = pi_obj&.fetch("id", nil)

        order = find_order(pi_id, pi_obj)
        return success_result(:no_order_found) unless order

        return success_result(:already_handled) if order.payment_failed?

        order.update_columns(
          status:                    "payment_failed",
          stripe_payment_intent_id:  pi_id
        )
        stripe_event.update!(order: order)

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
