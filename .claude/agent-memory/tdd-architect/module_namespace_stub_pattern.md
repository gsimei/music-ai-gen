---
name: module-namespace-stub-pattern
description: When testing classes inside an unimplemented module, define the module stub at the top of the test file to prevent load-time NameError while still getting the correct red-phase failure on the class call.
metadata:
  type: feedback
---

When writing TDD tests for a service namespace that doesn't yet exist (e.g., `MusicGenerator::MurekaClient`), the test file will fail at load time with `NameError: uninitialized constant MusicGenerator` — preventing tests from even running.

Add this guard at the top of each test file in the namespace:

```ruby
module MusicGenerator; end unless defined?(MusicGenerator)
```

This allows Rails to load the test class definition. Individual tests then fail with the correct red-phase error: `NameError: uninitialized constant MusicGenerator::MurekaClient`.

**Why:** Rails raises NameError at load time when the outer module constant is undefined. The inner class constant reference (e.g., `MurekaClient`) is fine — it's only the outer namespace that needs the stub.

**How to apply:** Any time a new service module is being introduced (e.g., `FooModule::SomeService`), add the module guard. Do NOT add it for existing modules like `LyricsGenerator` or `Stripe` — they are already defined by the application.

See also: [[stripe-handler-namespace]]
