# frozen_string_literal: true

module ApplicationHelper
  def brand_name
    BRANDS_CONFIG.fetch(:b2b).fetch(:display_name)
  end

  def campaign_price(order = nil)
    cents = order&.price_cents || BRANDS_CONFIG.dig(:b2b, :tiers, :starter, :price_cents)
    number_to_currency(cents / 100.0, unit: order && order.currency == "EUR" ? "€" : "R$ ", separator: ",", delimiter: ".", precision: cents % 100 == 0 ? 0 : 2, format: "%u%n")
  end

  def approved_music_asset(order)
    index = { "a" => 0, "b" => 1 }[order.approved_variant]
    return if index.nil?

    assets = order.order_assets.where(kind: "music_variant", variant_index: index)
    assets = assets.where(music_generation_id: order.approved_music_generation_id) if order.approved_music_generation_id
    assets.order(id: :desc).first
  end

  # Resolve uma chave de tradução com fallback por brand.
  # Se current_brand estiver definido (setado pelo around_action do ApplicationController),
  # tenta primeiro "brands.{brand}.{key}" e faz fallback para a chave global.
  #
  # Uso nas views:
  #   t_brand("site_name")           # => "ViraJingle" para b2b
  #   t_brand("errors.not_found")    # => fallback para chave global se nao houver override de brand
  def t_brand(key, **opts)
    return t(key, **opts) if current_brand.blank?

    t("brands.#{current_brand}.#{key}", **opts, default: ->(*) { t(key, **opts) })
  end
end
