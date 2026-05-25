# frozen_string_literal: true

module ApplicationHelper
  # Resolve uma chave de tradução com fallback por brand.
  # Se current_brand estiver definido (setado pelo around_action do ApplicationController),
  # tenta primeiro "brands.{brand}.{key}" e faz fallback para a chave global.
  #
  # Uso nas views:
  #   t_brand("hero.title")          # => "JinglePro" para b2b, "MusicaRegalo" para b2c
  #   t_brand("errors.not_found")    # => fallback para chave global se nao houver override de brand
  def t_brand(key, **opts)
    return t(key, **opts) if current_brand.blank?

    t("brands.#{current_brand}.#{key}", **opts, default: ->(*) { t(key, **opts) })
  end
end
