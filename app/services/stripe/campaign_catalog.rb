module Stripe
  # Stable lookup keys let test and live accounts keep their own Price IDs.
  # Explicit product IDs and idempotency keys make catalog setup repeatable.
  module CampaignCatalog
    class << self
      def sync!
        config = BRANDS_CONFIG.fetch(:b2b)
        [
          ensure_price(code: "campaign", quantity: 1, cents: config.dig(:tiers, :starter, :price_cents), currency: config.fetch(:currency)),
          ensure_price(code: Campaigns::PackOffer.code, quantity: Campaigns::PackOffer.quantity, cents: Campaigns::PackOffer.price_cents, currency: config.fetch(:currency))
        ]
      end

      def pack_price(order)
        pack = order.purchased_campaign_pack
        ensure_price(code: pack.offer_code, quantity: pack.quantity, cents: order.price_cents, currency: order.currency)
      end

      def ensure_price(code:, quantity:, cents:, currency:)
        lookup = "virajingle_#{code}_#{quantity}_#{currency.downcase}_#{cents}"
        price = Stripe::Price.list(lookup_keys: [ lookup ], active: true, limit: 1).data.first
        if price
          raise Stripe::InvalidRequestError.new("Catalog price does not match the saved order", "price") unless price.unit_amount == cents && price.currency == currency.downcase && price.type == "one_time"
          return price
        end

        product_id = "virajingle_#{code}_#{quantity}"
        begin
          Stripe::Product.retrieve(product_id)
        rescue Stripe::InvalidRequestError => error
          raise unless error.code == "resource_missing"

          Stripe::Product.create({ id: product_id, name: product_name(code, quantity),
            description: "Música personalizada, vídeo vertical e legenda. Pagamento único, sem assinatura.",
            metadata: { app: "virajingle", offer: code, campaign_credits: quantity } },
            { idempotency_key: "catalog-product-#{product_id}-v1" })
        end
        Stripe::Price.create({ product: product_id, currency: currency.downcase, unit_amount: cents,
          lookup_key: lookup, metadata: { app: "virajingle", offer: code, campaign_credits: quantity } },
          { idempotency_key: "catalog-price-#{lookup}-v1" })
      end

      private

      def product_name(code, quantity)
        name = BRANDS_CONFIG.fetch(:b2b).fetch(:display_name)
        code == "campaign" ? "#{name} — Campanha completa" : "#{name} — Black Friday: #{quantity} campanhas completas"
      end
    end
  end
end
