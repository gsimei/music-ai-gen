require "test_helper"

class ProductionSettingsTest < ActiveSupport::TestCase
  def environment
    ProductionSettings::REQUIRED_KEYS.index_with { "configured" }.merge(
      "APP_HOST" => "app.jinglepro.com.br", "MAILER_FROM" => "contato@jinglepro.com.br"
    )
  end

  test "production fails early with the names of missing settings, never their values" do
    error = assert_raises(ArgumentError) { ProductionSettings.load({}) }
    assert_includes error.message, "APP_HOST"
    assert_includes error.message, "RESEND_API_KEY"
    refute_includes error.message, "configured"
  end

  test "only a bare exact public hostname is accepted" do
    %w[https://app.jinglepro.com.br app.jinglepro.com.br:3000 .jinglepro.com.br *.jinglepro.com.br app.jinglepro.com.br/ evil.com,jinglepro.com.br].each do |host|
      assert_raises(ArgumentError, host) { ProductionSettings.load(environment.merge("APP_HOST" => host)) }
    end
    assert_equal "app.jinglepro.com.br", ProductionSettings.load(environment).host
  end

  test "SMTP requires TLS and uses the Resend key without changing the public mail origin" do
    settings = ProductionSettings.load(environment)
    assert_equal "smtp.resend.com", settings.smtp_settings[:address]
    assert_equal 587, settings.smtp_settings[:port]
    assert_equal "configured", settings.smtp_settings[:password]
    assert settings.smtp_settings[:enable_starttls]
    assert_equal "peer", settings.smtp_settings[:openssl_verify_mode]
    assert_equal "ViraJingle <contato@jinglepro.com.br>", settings.mailer_from
  end

  test "sender cannot contain another address or mail headers" do
    [ "a@b.com, c@d.com", "a@b.com\r\nBcc: c@d.com", "missing-address" ].each do |sender|
      assert_raises(ArgumentError) { ProductionSettings.load(environment.merge("MAILER_FROM" => sender)) }
    end
  end

  test "asset builds need no database or API credentials" do
    settings = ProductionSettings.load({}, build: true)
    assert_equal "build.invalid", settings.host
    assert_nil settings.smtp_settings[:password]
  end
end
