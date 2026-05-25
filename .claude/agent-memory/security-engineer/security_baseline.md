---
name: security-baseline
description: Security controls and known gaps established during Section 1 Setup Base review (2026-05-25)
metadata:
  type: project
---

Security baseline established in Section 1 Setup Base review (2026-05-25).

## Controls already in place
- Gemfile.lock committed (supply chain integrity)
- .gitignore uses `/.env*` pattern — covers .env and all variants at root
- config/master.key NOT tracked by git (/.env* and /config/*.key rules)
- filter_parameter_logging.rb covers: passw, email, secret, token, _key, crypt, salt, certificate, otp, ssn, cvv, cvc
- ApplicationPolicy defaults all actions to false (deny-by-default)
- Sentry: send_default_pii = false, enabled only in production/staging
- Devise: bcrypt stretches = 12 in production, 1 in test
- Devise: reconfirmable = true (email changes require re-confirmation)
- Devise: expire_all_remember_me_on_sign_out = true
- Devise: sign_out_via = :delete (CSRF protection on sign-out)
- Turbo/Hotwire compatible error/redirect statuses configured
- YAML.safe_load used for brands.yml (not unsafe YAML.load)

## Known gaps flagged in Section 1 review
- devise 4.9.4 has 2 active CVEs: CVE-2026-32700 (email race condition) and CVE-2026-40295 (open redirect via referrer in Timeoutable). Fix: upgrade to >= 5.0.4
- :lockable module NOT enabled — brute force protection missing
- :confirmable module NOT enabled (migration columns commented out) — no email verification
- :timeoutable NOT enabled — sessions never expire on inactivity
- :trackable NOT enabled — no login audit trail
- config.paranoid = true NOT set — user enumeration possible via different error messages
- force_ssl and assume_ssl commented out in production.rb
- config.hosts (DNS rebinding protection) commented out in production.rb
- Content Security Policy initializer fully commented out
- No rate limiting gem (Rack::Attack) installed
- Pundit after_action :verify_authorized NOT set in ApplicationController
- Sentry: no before_send filter for additional PII scrubbing
- Sentry: traces_sample_rate 0.1 may capture URL query params in traces
- Active Storage set to :local in production.rb (should be R2/S3 for production)
- BRANDS_CONFIG.freeze is shallow — nested hashes are mutable
- mailer_sender is placeholder "noreply@example.com" — not brand-specific yet
- sign_in_after_reset_password = true (default) — account takeover risk on shared device

**How to apply:** Use this list to check whether gaps have been addressed before signing off on future sections. Each feature section (auth flows, payments, storage) should revisit these.
