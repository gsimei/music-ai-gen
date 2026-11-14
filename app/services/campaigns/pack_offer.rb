module Campaigns
  module PackOffer
    class << self
      def config = BRANDS_CONFIG.fetch(:b2b).fetch(:campaign_pack)
      def code = config.fetch(:code)
      def quantity = config.fetch(:quantity)
      def price_cents = config.fetch(:price_cents)
      def starts_at = Time.iso8601(config.fetch(:starts_at))
      def ends_at = Time.iso8601(config.fetch(:ends_at))

      def available?(at: Time.current)
        at >= starts_at && at <= ends_at
      end

      def savings_cents
        BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :price_cents) * quantity - price_cents
      end
    end
  end
end
