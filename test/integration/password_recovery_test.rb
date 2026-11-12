require "test_helper"

class PasswordRecoveryFlowTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { host! "b2b.lvh.me" }

  test "the branded email link resets the password once and returns the merchant to sign in" do
    user = users(:customer_b2b)
    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end
    email = ActionMailer::Base.deliveries.last
    assert_equal "Crie uma nova senha — ViraJingle", email.subject
    url = URI(Nokogiri::HTML(email.html_part.body.decoded).at_css("a")["href"])
    token = Rack::Utils.parse_query(url.query).fetch("reset_password_token")
    get "#{url.path}?#{url.query}"
    assert_response :success
    assert_select 'img[alt="ViraJingle"][src^="/brand/"][src$="/virajingle-logo.svg"]'
    assert_select 'input[name="user[reset_password_token]"][value=?]', token

    new_password = "Minha-nova-senha-123!"
    patch user_password_path, params: { user: {
      reset_password_token: token, password: new_password, password_confirmation: new_password } }
    assert_redirected_to new_user_session_path
    assert user.reload.valid_password?(new_password)
    assert_nil user.reset_password_token
    encrypted = user.encrypted_password
    patch user_password_path, params: { user: {
      reset_password_token: token, password: "Outra-senha-123!", password_confirmation: "Outra-senha-123!" } }
    assert_response :unprocessable_entity
    assert_equal encrypted, user.reload.encrypted_password
  end

  test "the six hour validity advertised in the email is enforced" do
    user = users(:customer_b2b)
    token = user.send_reset_password_instructions
    encrypted = user.reload.encrypted_password
    travel_to user.reset_password_sent_at + User.reset_password_within + 1.minute do
      patch user_password_path, params: { user: {
        reset_password_token: token, password: "Senha-expirada-123!", password_confirmation: "Senha-expirada-123!" } }
      assert_response :unprocessable_entity
      assert_equal encrypted, user.reload.encrypted_password
    end
  end

  test "password recovery also renders the scoped templates through the default Devise mailer" do
    Devise.stub(:mailer, Devise::Mailer) do
      assert_emails 1 do
        post user_password_path, params: { user: { email: users(:customer_b2b).email } }
      end
      assert_response :redirect
      email = ActionMailer::Base.deliveries.last
      assert_includes email.html_part.body.decoded, "ViraJingle"
      assert_includes email.text_part.body.decoded, "ViraJingle"
      assert_includes email.html_part.body.decoded, "Criar nova senha"
    end
  end
end
