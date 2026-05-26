# frozen_string_literal: true

module ::Stripe
  module Handlers
    # Handles charge.refunded events from Stripe.
    #
    # Full refund (amount == amount_refunded):
    #   - Creates RefundRequest if order has a non-guest user
    #   - Cancels then refunds the order via AASM if in a cancellable state
    #
    # Partial refund (amount > amount_refunded):
    #   - Creates RefundRequest if order has a non-guest user
    #   - Does NOT change order status
    #
    # Returns :no_order_found gracefully when no order matches.
    class ChargeRefunded < BaseService
      CANCELLABLE_STATES = %w[
        pending payment_failed paid lyrics_drafting lyrics_ready
        lyrics_failed music_failed
      ].freeze

      attribute :stripe_event

      def call
        charge_obj = stripe_event.payload.dig("data", "object")
        charge_id  = charge_obj&.fetch("id", nil)
        pi_id      = charge_obj&.fetch("payment_intent", nil)

        order = find_order(charge_id, pi_id)
        return success_result(:no_order_found) unless order

        persist_charge_id(order, charge_id)

        full_refund = charge_obj["refunded"] == true ||
                      charge_obj["amount"] == charge_obj["amount_refunded"]

        if full_refund
          create_refund_request(order, charge_obj) unless guest_user?(order)
          cancel_and_refund(order)
        else
          create_refund_request(order, charge_obj) unless guest_user?(order)
        end

        stripe_event.update!(order: order)

        success_result
      end

      private

      def find_order(charge_id, pi_id)
        order = nil
        order = Order.find_by(stripe_charge_id: charge_id) if charge_id.present?
        order ||= Order.find_by(stripe_payment_intent_id: pi_id) if pi_id.present?
        order
      end

      def persist_charge_id(order, charge_id)
        return if order.stripe_charge_id.present? || charge_id.blank?

        order.update_columns(stripe_charge_id: charge_id)
      end

      def guest_user?(order)
        order.user.nil? || order.user.guest?
      end

      def create_refund_request(order, charge_obj)
        refund_id      = charge_obj.dig("refunds", "data", 0, "id")
        refunded_cents = charge_obj["amount_refunded"].to_i

        order.refund_requests.create!(
          user:                  order.user,
          reason:                "Stripe refund",
          reason_category:       "other",
          stripe_refund_id:      refund_id,
          refunded_amount_cents: refunded_cents,
          status:                "processed",
          resolved_at:           Time.current
        )
      end

      def cancel_and_refund(order)
        return unless CANCELLABLE_STATES.include?(order.status)

        order.cancel!
        order.refund!
      end
    end
  end
end
