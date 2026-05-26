# frozen_string_literal: true

module ::Stripe
  module Handlers
    # Handles checkout.session.completed events.
    #
    # Transitions order from pending → paid via AASM mark_paid! event.
    # Associates the StripeEvent with the order.
    # Idempotent: returns :already_handled if order is already paid.
    class CheckoutSessionCompleted < BaseService
      attribute :stripe_event

      def call
        session_obj = stripe_event.payload.dig("data", "object")
        session_id  = session_obj&.fetch("id", nil)

        order = find_order(session_id, session_obj)
        return failure_result("order_not_found") unless order

        return success_result(:already_handled) if order.paid?

        ActiveRecord::Base.transaction do
          order.stripe_payment_intent_id = session_obj["payment_intent"]
          order.paid_at                  = Time.current
          stripe_event.order             = order
          order.mark_paid!
          stripe_event.save!
        end

        success_result(order)
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[CheckoutSessionCompleted] RecordInvalid for order #{order&.id}: #{e.message}"
        failure_result(e.message)
      rescue AASM::InvalidTransition => e
        Rails.logger.error "[CheckoutSessionCompleted] InvalidTransition for order #{order&.id}: #{e.message}"
        failure_result(e.message)
      end

      private

      def find_order(session_id, session_obj)
        return nil if session_id.blank?

        Order.find_by(stripe_session_id: session_id) ||
          Order.find_by(reference: session_obj&.dig("client_reference_id"))
      end
    end
  end
end
