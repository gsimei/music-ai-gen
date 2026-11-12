class UsersMailerPreview < ActionMailer::Preview
  def reset_password_instructions
    Users::Mailer.reset_password_instructions(User.new(email: "voce@exemplo.com"), "token-de-exemplo")
  end
end
