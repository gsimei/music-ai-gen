# frozen_string_literal: true

class BrandLocaleResolver < BaseService
  attribute :host, :string
  attribute :accept_language, :string
  attribute :locale_cookie, :string
  attribute :locale_param, :string

  validates :host, presence: true

  def call
    return failure_result(errors) unless valid?

    brand = detect_brand
    return failure_result(:unknown_host) if brand.nil?

    locale = detect_locale(brand)

    success_result(brand: brand.to_s, locale: locale)
  end

  private

  def normalized_host
    @normalized_host ||= host.to_s.split(":").first.to_s.sub(/\Awww\./, "")
  end

  def detect_brand
    BRANDS_CONFIG.each do |brand_key, config|
      return brand_key if Array(config[:hosts]).include?(normalized_host)
    end

    if rails_env.development? || rails_env.test?
      Rails.logger.warn("[BrandLocaleResolver] unknown host '#{normalized_host}' — falling back to :b2c")
      return :b2c
    end

    nil
  end

  def detect_locale(brand_key)
    config = BRANDS_CONFIG[brand_key]
    supported = Array(config[:supported_locales]).map(&:to_sym)
    default = config[:default_locale].to_sym

    return default if supported.empty?

    # .it host forces italian
    return :it if normalized_host.end_with?(".it") && supported.include?(:it)

    # Try param (dev only)
    if rails_env.development? && locale_param.present?
      sym = locale_param.to_sym
      return sym if supported.include?(sym)
    end

    # Try cookie
    if locale_cookie.present?
      sym = locale_cookie.to_sym
      return sym if supported.include?(sym)
    end

    # Try Accept-Language
    if accept_language.present?
      detected = parse_accept_language(accept_language, supported)
      return detected if detected
    end

    default
  end

  def parse_accept_language(header, supported)
    header.to_s.split(",").each do |part|
      code = part.split(";").first.to_s.strip.split("-").first.to_s.downcase
      sym = code.to_sym
      return sym if supported.include?(sym)
    end
    nil
  end

  # Extracted for testability — allows stubbing Rails.env in unit tests
  # without monkey-patching the Rails module itself.
  def rails_env
    Rails.env
  end
end
