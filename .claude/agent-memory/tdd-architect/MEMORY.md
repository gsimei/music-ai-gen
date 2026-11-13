# TDD Architect Memory Index

- [WebMock Setup](webmock_setup.md) — WebMock requires explicit `require "webmock/minitest"` in test_helper; not auto-loaded
- [Stripe Handler Namespace](stripe_handler_namespace.md) — Stripe handlers use `Stripe::Handlers::` namespace; tests fail with NameError on `Stripe::Handlers` until module is defined
- [Fixture Conventions](fixture_conventions.md) — Existing fixture patterns and IDs to be aware of when adding new fixtures
- [Module Namespace Stub Pattern](module_namespace_stub_pattern.md) — Add `module Foo; end unless defined?(Foo)` guard when testing unimplemented namespaces to get correct red-phase NameError
- [Fixture: preview_ready needs briefing](fixture_preview_ready.md) — b2c_preview_ready order needs a briefing fixture; any music-state order must have one
- [ActionCable::TestHelper in Jobs](actioncable_testhelper.md) — assert_broadcasts requires explicit `include ActionCable::TestHelper` in ActiveJob::TestCase subclasses
- [Criar test patterns](criar_test_patterns.md) — system test setup, const stubbing, vacuous-loop and mobile-click traps for the Criar screen
