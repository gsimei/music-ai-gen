---
name: stripe-handler-namespace
description: Stripe services use Stripe:: and Stripe::Handlers:: namespaces; module must be explicitly defined
metadata:
  type: project
---

The Stripe integration uses a two-level namespace:
- `Stripe::CheckoutBuilder` — top-level service
- `Stripe::WebhookHandler` — top-level service
- `Stripe::Handlers::CheckoutSessionCompleted` — event-specific handlers
- `Stripe::Handlers::PaymentIntentFailed`
- `Stripe::Handlers::ChargeRefunded`

**Why:** Tests fail with `NameError: uninitialized constant Stripe::Handlers` at the class definition line if the `Stripe::Handlers` module doesn't exist yet. The backend-architect must define both the `Stripe` module (already exists as a gem constant) and the `Stripe::Handlers` module wrapper.

**How to apply:** When writing tests, use `Stripe::Handlers::HandlerName` fully qualified. When implementing, create `app/services/stripe/handlers/` directory with a `module Stripe; module Handlers` wrapper or autoload configuration.
