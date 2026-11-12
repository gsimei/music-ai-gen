require_relative "resend_mail_settings"

# Shared origins and credentials for the web process, jobs, and Devise mailer.
# Asset compilation is the only mode that may boot without runtime secrets.
class ProductionSettings
  REQUIRED_KEYS = %w[
    APP_HOST MAILER_FROM RESEND_API_KEY DATABASE_URL CACHE_DATABASE_URL
    QUEUE_DATABASE_URL CABLE_DATABASE_URL STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET MUREKA_API_KEY
  ].freeze
  HOSTNAME = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/

  attr_reader :host, :mailer_from, :smtp_settings

  def self.load(env = ENV, build: false)
    new(env, build: build)
  end

  def initialize(env, build:)
    unless build
      missing = REQUIRED_KEYS.select { |key| env[key].to_s.strip.empty? }
      raise ArgumentError, "Missing production settings: #{missing.join(', ')}" if missing.any?
    end

    @host = env["APP_HOST"].to_s.strip.downcase
    @host = "build.invalid" if build && @host.empty?
    raise ArgumentError, "APP_HOST must be a bare public hostname, without protocol, port, or path" unless HOSTNAME.match?(@host)

    mail = ResendMailSettings.load(env, host: @host, build: build)
    @mailer_from = mail.mailer_from
    @smtp_settings = mail.smtp_settings
  end
end
