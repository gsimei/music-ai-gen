module Stripe
  # Shared by signed webhooks and server-to-server reconciliation after Checkout.
  class CheckoutFulfillment < BaseService
    attribute :order
    attribute :session_data

    def call
      order.with_lock do
        if order.campaign || order.purchased_campaign_pack
          return failure_result("payment_not_confirmed") unless session_data["id"] == order.stripe_session_id &&
            session_data["payment_status"] == "paid" && session_data["amount_total"] == order.price_cents &&
            session_data["currency"].to_s.downcase == order.currency.downcase
        end
        return success_result(:already_handled) unless order.pending? || order.payment_failed?
        order.stripe_payment_intent_id = session_data["payment_intent"]
        order.paid_at = Time.current
        order.mark_paid!
      end
      success_result(order)
    rescue ActiveRecord::RecordInvalid, AASM::InvalidTransition => error
      failure_result(error.message)
    end
  end
end
