# frozen_string_literal: true

module ::Stripe
  # Builds a Stripe Checkout Session for a pending Order.
  #
  # Responsibilities:
  # - Validates the order is in pending status before calling Stripe
  # - Creates a Stripe::Checkout::Session with correct line items and metadata
  # - Persists the session ID on the order via update_columns (no callbacks)
  # - Returns success_result(session) or failure_result on API/validation error
  class CheckoutBuilder < BaseService
    attribute :order

    def call
      return failure_result("order_not_pending") unless order.pending?

      session = create_stripe_session
      order.update_columns(stripe_session_id: session.id)
      success_result({ url: session.url, id: session.id })
    rescue ::Stripe::StripeError, StandardError => e
      Rails.logger.error "[CheckoutBuilder] Stripe error for order #{order&.id}: #{e.message}"
      failure_result(e.message)
    end

    private

    def create_stripe_session
      ::Stripe::Checkout::Session.create(
        mode: "payment",
        line_items: [ line_item ],
        customer_email: order.delivery_email,
        client_reference_id: order.reference,
        success_url: success_url,
        cancel_url: cancel_url,
        locale: order.locale,
        metadata: {
          order_id: order.id,
          reference: order.reference,
          brand: order.brand
        }
      )
    end

    def line_item
      {
        price_data: {
          currency: order.currency.downcase,
          product_data: { name: product_name },
          unit_amount: order.price_cents
        },
        quantity: 1
      }
    end

    def product_name
      brand_config = BRANDS_CONFIG.dig(order.brand.to_sym)
      display_name = brand_config&.dig(:display_name) || "Music AI Gen"
      tier_label   = order.tier.to_s.capitalize
      "#{display_name} — #{tier_label}"
    end

    def success_url
      routes.order_url(order, host: brand_host(order.brand))
    end

    def cancel_url
      routes.order_url(order, host: brand_host(order.brand))
    end

    def brand_host(brand)
      BRANDS_CONFIG.dig(brand.to_sym, :hosts).first
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
