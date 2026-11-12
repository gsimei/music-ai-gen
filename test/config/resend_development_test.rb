require "test_helper"
require "open3"

class ResendDevelopmentTest < ActiveSupport::TestCase
  test "development uses the verified sender only when real sending is explicitly enabled" do
    settings = boot_mail_settings("development", "resend")
    assert_equal "smtp", settings.fetch("delivery_method")
    assert_equal "smtp.resend.com", settings.fetch("smtp_address")
    assert settings.fetch("starttls")
    assert settings.fetch("raise_delivery_errors")
    assert_equal "ViraJingle <avisos@virajingle.com.br>", settings.fetch("sender")
    assert_equal "localhost", settings.fetch("link_host")
  end

  test "test environment keeps deliveries in memory even with a key and sending enabled" do
    settings = boot_mail_settings("test", "resend")
    assert_equal "test", settings.fetch("delivery_method")
  end

  test "development password recovery renders before and after code reloading" do
    settings = boot_mail_settings("development", "resend", reload_preview: true)
    assert_equal 2, settings.fetch("previews").size
    settings.fetch("previews").each do |preview|
      assert_equal "Users::Mailer", preview.fetch("mailer")
      assert preview.fetch("html")
      assert preview.fetch("text")
      assert preview.fetch("logo")
    end
  end

  private

  def boot_mail_settings(environment, method, reload_preview: false)
    script = <<~RUBY
      previews = []
      if #{reload_preview}
        2.times do |pass|
          Rails.application.reloader.reload! if pass.positive?
          email = Devise.mailer.reset_password_instructions(User.new(email: "preview@example.test"), "test-token").message
          previews << {
            mailer: Devise.mailer.name,
            html: email.html_part.body.decoded.include?("ViraJingle"),
            text: email.text_part.body.decoded.include?("ViraJingle"),
            logo: email.attachments["virajingle-logo.png"].present?
          }
        end
      end
      puts "MAIL_SETTINGS=" + JSON.generate(
        delivery_method: ActionMailer::Base.delivery_method,
        smtp_address: ActionMailer::Base.smtp_settings[:address],
        starttls: ActionMailer::Base.smtp_settings[:enable_starttls],
        raise_delivery_errors: ActionMailer::Base.raise_delivery_errors,
        sender: Devise.mailer_sender,
        link_host: ActionMailer::Base.default_url_options[:host],
        previews: previews
      )
    RUBY
    output, errors, status = Open3.capture3(
      { "RAILS_ENV" => environment, "MAIL_DELIVERY_METHOD" => method,
        "MAILER_FROM" => "avisos@virajingle.com.br", "RESEND_API_KEY" => "re_test_not_a_real_key" },
      Rails.root.join("bin/rails").to_s, "runner", script
    )
    assert status.success?, errors
    JSON.parse(output.lines.find { |line| line.start_with?("MAIL_SETTINGS=") }.delete_prefix("MAIL_SETTINGS="))
  end
end
