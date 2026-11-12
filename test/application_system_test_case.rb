require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 1000 ] do |options|
    options.add_argument("--disable-dev-shm-usage") if ENV["CI"]
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
  end

  setup do
    WebMock.disable_net_connect!(allow_localhost: true)
    Capybara.default_max_wait_time = 10
  end
end
