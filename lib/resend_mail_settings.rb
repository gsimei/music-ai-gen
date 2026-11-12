require "uri"

# Shared by production and explicitly enabled development delivery. Tests keep
# their in-memory delivery adapter regardless of the developer's credentials.
class ResendMailSettings
  attr_reader :mailer_from, :smtp_settings

  def self.load(env = ENV, host: nil, build: false)
    new(env, host: host, build: build)
  end

  def initialize(env, host:, build:)
    unless build
      missing = %w[RESEND_API_KEY MAILER_FROM].select { |key| env[key].to_s.strip.empty? }
      raise ArgumentError, "Missing mail settings: #{missing.join(', ')}" if missing.any?
    end

    sender = env["MAILER_FROM"].to_s.strip
    sender = "no-reply@build.invalid" if build && sender.empty?
    unless URI::MailTo::EMAIL_REGEXP.match?(sender) && !sender.match?(/[\r\n,<>]/)
      raise ArgumentError, "MAILER_FROM must contain one email address"
    end

    @mailer_from = "ViraJingle <#{sender}>"
    @smtp_settings = {
      address: "smtp.resend.com", port: 587, domain: host || sender.split("@").last,
      user_name: "resend", password: env["RESEND_API_KEY"], authentication: :plain,
      enable_starttls: true, openssl_verify_mode: "peer", open_timeout: 10, read_timeout: 15
    }
  end
end
