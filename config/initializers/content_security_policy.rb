Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.object_src :none
    policy.frame_ancestors :none
    policy.script_src :self, "https://cdnjs.cloudflare.com"
    # Existing style attributes and GSAP animations require inline styles.
    # Nonces apply only to scripts so they do not disable this compatibility.
    policy.style_src :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src :self, "https://fonts.gstatic.com"
    policy.img_src :self, :data, :blob
    policy.media_src :self, :blob, :https
    policy.form_action :self, "https://checkout.stripe.com"
    if Rails.env.production?
      policy.connect_src :self, "wss://#{config.x.public_host}"
      policy.upgrade_insecure_requests true
    else
      policy.connect_src :self, :ws
    end
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
