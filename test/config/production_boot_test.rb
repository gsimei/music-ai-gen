require "test_helper"
require "open3"

class ProductionBootTest < ActiveSupport::TestCase
  test "the production middleware enforces exact hosts and HTTPS while keeping health checks available" do
    # Isolated production boot, with no real API credentials or outbound delivery.
    script = <<~RUBY
      require "rack/mock"
      checks = [
        ["http://app.jinglepro.test/", {}],
        ["https://app.jinglepro.test/", {}],
        ["https://attacker.test/", {}],
        ["https://app.jinglepro.test.attacker.test/", {}],
        ["https://app.jinglepro.test/", {"HTTP_X_FORWARDED_HOST" => "attacker.test"}],
        ["https://app.jinglepro.test/", {"HTTP_X_FORWARDED_HOST" => "app.jinglepro.test, attacker.test"}],
        ["http://127.0.0.1/up", {}]
      ].map do |url, headers|
        status, headers, body = Rails.application.call(Rack::MockRequest.env_for(url, {"HTTP_HOST" => URI(url).host}.merge(headers)))
        body.close if body.respond_to?(:close)
        {status: status, location: headers["location"], hsts: headers["strict-transport-security"], cookie: headers["set-cookie"]}
      end
      puts "PRODUCTION_CHECK=" + JSON.generate(checks)
    RUBY
    output, errors, status = Open3.capture3(
      { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "APP_HOST" => "app.jinglepro.test",
        "MAILER_FROM" => "contato@jinglepro.test", "BEHIND_SSL_PROXY" => "false", "SENTRY_DSN" => "" },
      Rails.root.join("bin/rails").to_s, "runner", script
    )
    assert status.success?, errors
    checks = JSON.parse(output.lines.find { |line| line.start_with?("PRODUCTION_CHECK=") }.delete_prefix("PRODUCTION_CHECK="))
    assert_equal 301, checks[0]["status"]
    assert_equal "https://app.jinglepro.test/", checks[0]["location"]
    assert_equal 200, checks[1]["status"]
    assert_match /max-age=/, checks[1]["hsts"]
    (2..5).each { |index| assert_equal 403, checks[index]["status"] }
    assert_equal 200, checks[6]["status"]
  end
end
