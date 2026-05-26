# TDD Architect Memory Index

- [WebMock Setup](webmock_setup.md) — WebMock requires explicit `require "webmock/minitest"` in test_helper; not auto-loaded
- [Stripe Handler Namespace](stripe_handler_namespace.md) — Stripe handlers use `Stripe::Handlers::` namespace; tests fail with NameError on `Stripe::Handlers` until module is defined
- [Fixture Conventions](fixture_conventions.md) — Existing fixture patterns and IDs to be aware of when adding new fixtures
