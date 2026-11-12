# Render an illustrative message, without delivery or a persisted account.
require "base64"

Users::Mailer.default_url_options = { host: "localhost", port: 3000, protocol: "http" }
message = Users::Mailer.reset_password_instructions(User.new(email: "voce@exemplo.com"), "token-de-exemplo").message
html = message.html_part.body.decoded
message.attachments.each do |attachment|
  html = html.gsub("cid:#{attachment.cid}", "data:#{attachment.mime_type};base64,#{Base64.strict_encode64(attachment.body.decoded)}")
end
Rails.root.join("design/virajingle/password-reset-preview.html").write(html)
puts "Email preview rendered; no message delivered."
