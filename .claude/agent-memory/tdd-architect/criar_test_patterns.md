---
name: criar-test-patterns
description: How tests for the Criar (campaigns/new) screen are built here - system test setup, constant stubbing, red-phase traps
metadata:
  type: reference
---

- System tests: `ApplicationSystemTestCase` + `Warden::Test::Helpers` (`login_as users(:customer_b2b), scope: :user`); stub Stripe with `stub_request(:post, "https://api.stripe.com/v1/checkout/sessions").to_raise(Stripe::APIConnectionError...)` so submit saves the campaign and lands on the step-3 page with "Sua campanha está salva". Mobile = `execute_cdp("Emulation.setDeviceMetricsOverride", ..., mobile: true)`, reset in teardown.
- Stub a constant (e.g. `Campaigns::PhotoLimit::INITIAL`) with `silence_warnings { Mod.const_set(:X, v) }` in `ensure`-restored helper; views read it at render time.
- Red-phase trap: loops over empty `css_select` results pass vacuously - assert the count first. `ApplicationController.helpers` has no route helpers (`rails_blob_path` missing), use the test's own.
- Chips are clipped radios: click the `label`, scroll it to center first on mobile (fixed action bar intercepts clicks).
- `find(...).click` on aria-label buttons: Capybara `click_button` does not match aria-label here.
- Headless Chrome plays the local `/demos/genres/*.mp3` after a real Capybara click (user gesture) and fires `timeupdate`; startup can take >2 s, so wait with `assert_selector ..., wait: 12` for the clock to leave "0:00". `audio.played.length == 0` proves nothing played.
- `test_payment_campaign_path` does not exist in the test env (route is development-only): the dev-only "Testar sem cobrança" block cannot be rendered by stubbing `Rails.env`; guard it with a source scan of `app/views/campaigns/new*` instead.
- `campaigns/_sound_fields` is rendered only by the Criar's step 2; the studio uses plain `select`s (`order_chat/_creation_form`). After the redesign it is an orphan: test it with `ApplicationController.render(inline: ...)`.
- Nokogiri NodeSet has no `.second`; use `[1]`. Wrap fetches of required nodes in a helper that `assert`s presence so red phase shows assertion failures, not NoMethodError.
- BRANDS_CONFIG is deep frozen: swap the whole constant (`const_set` inside `silence_warnings`, restore in `ensure`) to prove a view reads it. `Campaigns::MusicRounds::LIMIT` the same way.
