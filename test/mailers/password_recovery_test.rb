require "test_helper"

class PasswordRecoveryTest < ActionMailer::TestCase
  test "Devise recovery uses our configured sender and trusted HTTPS origin" do
    original_options = ActionMailer::Base.default_url_options
    ActionMailer::Base.default_url_options = { host: "virajingle.com.br", protocol: "https" }
    Devise.stub(:mailer_sender, "ViraJingle <avisos@virajingle.com.br>") do
      email = Devise.mailer.reset_password_instructions(users(:customer_b2b), "test-reset-token").message
      assert_equal [ "avisos@virajingle.com.br" ], email.from
      assert_equal [ "ViraJingle" ], email[:from].display_names
      assert_equal "Crie uma nova senha — ViraJingle", email.subject
      assert email.multipart?
      assert email.text_part
      assert email.html_part
      html = email.html_part.body.decoded
      assert_includes html, "Criar nova senha"
      assert_includes html, "6 horas"
      assert_includes html, "Se você não fez esse pedido"
      refute_includes html, "Hello"
      refute_includes html, "JinglePro"
      assert_includes email.text_part.body.decoded, "virajingle.com.br/users/password/edit?reset_password_token=test-reset-token"
      assert_includes email.text_part.body.decoded, "6 horas"
      assert email.attachments["virajingle-logo.png"].inline?
      document = Nokogiri::HTML(html)
      assert_equal "pt-BR", document.at_css("html")["lang"]
      assert_equal "ViraJingle", document.at_css("img")["alt"]
      assert document.at_css("img")["src"].start_with?("cid:")
      link = document.at_css("a")["href"]
      assert_equal "virajingle.com.br", URI(link).host
      assert_equal "https", URI(link).scheme
      assert_includes link, "reset_password_token=test-reset-token"
    end
  ensure
    ActionMailer::Base.default_url_options = original_options
  end

  test "account notifications stay in Portuguese when the caller uses another locale" do
    I18n.with_locale(:en) do
      email = Devise.mailer.reset_password_instructions(users(:customer_b2b), "preview-token").message
      assert_equal "Crie uma nova senha — ViraJingle", email.subject
      assert_includes email.text_part.body.decoded, "Olá!"
      assert_equal :en, I18n.locale
    end
  end

  test "unlock and account change emails use the same new brand and readable text alternative" do
    user = users(:customer_b2b)
    [ Devise.mailer.unlock_instructions(user, "unlock-token"), Devise.mailer.password_change(user), Devise.mailer.email_changed(user) ].each do |delivery|
      email = delivery.message
      assert_includes email.subject, "ViraJingle"
      assert_includes email.html_part.body.decoded, "ViraJingle"
      assert email.text_part
      refute_includes email.text_part.body.decoded, "Hello"
      assert email.attachments["virajingle-logo.png"].inline?
    end
  end
end
