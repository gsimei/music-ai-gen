# frozen_string_literal: true

class BrandConstraint
  def initialize(brand)
    @hosts = BRANDS_CONFIG.dig(brand, :hosts).map(&:to_s)
  end

  def matches?(request)
    host = request.host.to_s.split(":").first.sub(/\Awww\./, "")
    @hosts.include?(host)
  end
end
