# Isolated checkout verification: use only the local test database and synthetic
# API keys, without reading project dotenv files or contacting paid providers.
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "postgresql:///music_ai_gen_test"
ENV["PGHOST"] = "/tmp"
ENV["PGPORT"] = "5432"
ENV["STRIPE_SECRET_KEY"] = "sk_test_local_isolated"
ENV["MUREKA_API_KEY"] = "test_mureka_isolated"
require_relative "../config/boot"
require "rails"
require "dotenv"
require "dotenv/rails"
Dotenv::Rails.files = [ File::NULL ]
$LOAD_PATH.unshift(File.expand_path("../test", __dir__))
paths = ARGV.empty? ? %w[
  test/integration/guest_campaign_creation_test.rb
  test/system/merchant_checkout_test.rb
  test/system/guest_campaign_authentication_test.rb
  test/system/campaign_browser_media_test.rb
] : ARGV.dup
ARGV.clear
paths.each { |file| require File.expand_path(file, Rails.root || File.expand_path("..", __dir__)) }
