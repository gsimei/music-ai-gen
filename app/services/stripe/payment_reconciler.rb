module Stripe
  class PaymentReconciler < BaseService
    attribute :order

    def call
      return success_result(:already_handled) unless order.pending?
      return failure_result("checkout_missing") if order.stripe_session_id.blank?

      # Use only our persisted session ID, never a caller-supplied ID or status.
      session = Stripe::Checkout::Session.retrieve(order.stripe_session_id)
      CheckoutFulfillment.call(order: order, session_data: session.to_hash.deep_stringify_keys)
    rescue Stripe::StripeError => error
      Rails.logger.warn("[PaymentReconciler] order=#{order.id} error=#{error.class.name}")
      failure_result("payment_check_unavailable")
    end
  end
end
