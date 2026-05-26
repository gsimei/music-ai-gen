---
name: webmock-setup
description: WebMock is in the :test Gemfile group but must be explicitly required in test_helper.rb
metadata:
  type: feedback
---

WebMock requires `require "webmock/minitest"` added to `test/test_helper.rb`. It is NOT auto-loaded even though it's in the `:test` group.

**Why:** Without the explicit require, `stub_request` is undefined in ActiveSupport::TestCase subclasses. Discovered during Section 8 TDD (Stripe services).

**How to apply:** Always verify `require "webmock/minitest"` is present in test_helper.rb before writing tests that use `stub_request`. If missing, add it as part of the TDD setup step.
