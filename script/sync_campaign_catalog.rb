# Creates/reuses catalog entries; never charges a customer or creates a payment link.
require "json"
require "fileutils"

Stripe.open_timeout = 5
Stripe.read_timeout = 15
Stripe.max_network_retries = 1

if ARGV.delete("--live")
  expected_account = Stripe::Account.retrieve.id
  # Reuse the Stripe CLI connection without printing or copying credentials.
  content = File.read(File.expand_path("~/.config/stripe/config.toml"))
  profile = content.split(/^\[default\]\s*$/).last.to_s.split(/^\[/).first.to_s
  key = profile[/^live_mode_api_key\s*=\s*['"]([^'"]+)['"]/, 1]
  abort "A conexão de produção da Stripe CLI não está disponível." unless key.to_s.start_with?("sk_live_", "rk_live_")
  expires = profile[/^live_mode_key_expires_at\s*=\s*['"]([^'"]+)['"]/, 1]
  abort "A conexão de produção da Stripe CLI expirou. Execute stripe login na conta do ViraJingle." if expires.present? && Date.iso8601(expires) < Date.current
  Stripe.api_key = key
end

account = Stripe::Account.retrieve
abort "A conta de produção difere da conta configurada no ViraJingle. Nenhum produto foi criado." if expected_account && account.id != expected_account
prices = Stripe::CampaignCatalog.sync!
report = { account_id: account.id, mode: prices.first.livemode ? "live" : "test", synced_at: Time.current.iso8601,
  prices: prices.map { |price| { id: price.id, product: price.product, unit_amount: price.unit_amount,
    currency: price.currency, lookup_key: price.lookup_key, livemode: price.livemode } } }
destination = Rails.root.join("output/campaigns/2026-11-14-black-friday/fontes")
FileUtils.mkdir_p(destination)
File.write(destination.join("stripe-catalog-#{report[:mode]}.json"), JSON.pretty_generate(report))
puts JSON.generate(report)
