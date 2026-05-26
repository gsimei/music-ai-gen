---
name: stripe-integration-notes
description: Key facts about Stripe integration decisions confirmed in codebase — gems, conventions, idempotency, webhook rules
metadata:
  type: project
---

Stripe gem `~> 13.0` and WebMock `~> 3.23` are already in the Gemfile.

Webhook contract (from SPEC.md + CLAUDE.md):
- Always return HTTP 200 when HMAC signature is valid — never 4xx/5xx on valid events
- Processing is fully asynchronous via `StripeWebhookProcessorJob`
- Idempotency enforced via `stripe_events.stripe_event_id` (unique index in DB)

`StripeEvent` model already exists with statuses: `pending`, `processed`, `failed`, `skipped`.
`already_processed?` alias for `processed?` already defined.

`RefundRequest` model already exists with statuses: `pending`, `approved`, `denied`, `processed`.
`reason_category` must be one of: `quality_issue`, `late_delivery`, `wrong_voice`, `technical`, `not_as_expected`, `other`.

`Order` AASM events relevant to Stripe:
- `mark_paid!` → transitions `:pending` → `:paid`, after_commit enqueues `GenerateLyricsJob`
- There is NO `mark_payment_failed!` event — must be handled via `Order.update_columns(status: :payment_failed)` directly (bypasses AASM) or add a new AASM event.
- `cancel!` → valid from `:pending`, `:payment_failed`, `:paid`, `:lyrics_drafting`, `:lyrics_ready`, `:lyrics_failed`, `:music_failed`
- `refund!` → valid from `:cancelled` only

**Why:** AASM `requires_new_transaction: false` is set, so state transitions must be wrapped carefully within transactions.

**How to apply:** When `payment_intent.payment_failed` arrives, use `update_columns` to set `status: :payment_failed` and `stripe_payment_intent_id` directly (or fire a `fail_payment!` AASM event if added). Do not call `mark_paid!` — that event only goes from `:pending`.
