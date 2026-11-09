# frozen_string_literal: true

module ::Stripe
  # Builds a Stripe Checkout Session for an unpaid Order.
  #
  # Responsibilities:
  # - Validates the order is pending or has a failed payment before calling Stripe
  # - Creates a Stripe::Checkout::Session with correct line items and metadata
  # - Persists the session ID on the order via update_columns (no callbacks)
  # - Returns success_result(session) or failure_result on API/validation error
  class CheckoutBuilder < BaseService
    attribute :order
    attribute :host, :string

    def call
      return failure_result("order_not_pending") unless order.pending? || order.payment_failed?

      order.with_lock do
        return failure_result("order_not_pending") unless order.pending? || order.payment_failed?
        if order.campaign && order.stripe_session_id.present?
          previous = ::Stripe::Checkout::Session.retrieve(order.stripe_session_id)
          if previous.payment_status == "paid"
            result = ::Stripe::CheckoutFulfillment.call(order: order, session_data: previous.to_hash.deep_stringify_keys)
            return result if result.failure?
            return success_result({ url: routes.campaign_url(order.campaign, payment: "processing", host: resolved_host, protocol: url_protocol), id: previous.id })
          end
          return success_result({ url: previous.url, id: previous.id }) if previous.status == "open"
          return failure_result("payment_processing") unless previous.status == "expired"
        end
        session = create_stripe_session
        order.update_columns(stripe_session_id: session.id)
        success_result({ url: session.url, id: session.id })
      end
    rescue ::Stripe::StripeError, StandardError => e
      Rails.logger.error "[CheckoutBuilder] Stripe error for order #{order&.id}: #{e.message}"
      failure_result(e.message)
    end

    private

    def create_stripe_session
      ::Stripe::Checkout::Session.create(
        mode: "payment",
        payment_method_types: [ "card" ],
        line_items: [ line_item ],
        customer_email: order.delivery_email,
        client_reference_id: order.reference,
        success_url: success_url,
        cancel_url: cancel_url,
        locale: order.locale == "pt" ? "pt-BR" : order.locale,
        payment_intent_data: { metadata: { order_id: order.id, reference: order.reference, brand: order.brand } },
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
      return "JinglePro — Campanha com música e vídeo" if order.campaign

      brand_config = BRANDS_CONFIG.dig(order.brand.to_sym)
      display_name = brand_config&.dig(:display_name) || "Music AI Gen"
      tier_label   = order.tier.to_s.capitalize
      "#{display_name} — #{tier_label}"
    end

    def success_url
      return routes.campaign_url(order.campaign, payment: "processing", host: resolved_host, protocol: url_protocol) if order.campaign
      routes.order_chat_url(order_id: order.id, host: resolved_host, protocol: url_protocol)
    end

    def cancel_url
      return routes.campaign_url(order.campaign, host: resolved_host, protocol: url_protocol) if order.campaign
      routes.order_url(order, host: resolved_host, protocol: url_protocol)
    end

    def url_protocol
      Rails.env.production? ? "https" : "http"
    end

    def resolved_host
      host.presence || BRANDS_CONFIG.dig(order.brand.to_sym, :hosts).first
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
