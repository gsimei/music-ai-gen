class GenerationCost < ApplicationRecord
  PRICING_VERSION = "2026-11-09"
  SONG_PRICES = { "mureka-7.6" => "0.03", "mureka-o2" => "0.045", "mureka-8" => "0.045", "mureka-9" => "0.045", "mureka-9.5" => "0.15" }.freeze

  belongs_to :order
  belongs_to :music_generation, optional: true
  validates :operation, :provider, :pricing_version, presence: true
  validates :status, inclusion: { in: %w[estimated uncertain unpriced] }

  def self.record!(order:, operation:, provider:, model:, usd: nil, usage: {}, status: nil, **attributes)
    rate = BigDecimal(ENV.fetch("COST_USD_BRL", "6"))
    raise ArgumentError, "COST_USD_BRL must be positive" unless rate.positive?
    create!(order: order, operation: operation, provider: provider, model: model,
      estimated_usd: usd, usd_brl: rate, estimated_brl: usd && BigDecimal(usd.to_s) * rate,
      usage: usage, status: status || (usd ? "estimated" : "unpriced"), pricing_version: PRICING_VERSION, **attributes)
  end

  def self.song_price(model)
    SONG_PRICES[model]&.to_d
  end
end
