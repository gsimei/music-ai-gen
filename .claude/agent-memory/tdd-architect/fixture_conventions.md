---
name: fixture-conventions
description: Key fixture names, stripe IDs, and patterns used across the test suite
metadata:
  type: project
---

## Order fixtures (test/fixtures/orders.yml)

Key fixtures and their stripe fields:
- `b2c_pending` — status: pending, no stripe IDs (use update_columns in tests to add)
- `b2c_paid_with_stripe` — status: paid, stripe_session_id: "cs_test_paid_session_001", stripe_payment_intent_id: "pi_test_paid_intent_001"
- `b2c_payment_failed` — status: payment_failed, stripe_payment_intent_id: "pi_test_failed_intent_001"
- `b2b_pending_with_stripe` — status: pending, brand: b2b, tier: starter, price_cents: 7900
- `b2c_cancelled` — status: cancelled (eligible for refund! transition)
- `guest_order` — user: guest_user (guest: true) — use update_columns to change status for refund tests

## StripeEvent fixtures (test/fixtures/stripe_events.yml)

- `checkout_completed` — status: processed (use for idempotency tests)
- `payment_failed_event` — status: pending, event_type: payment_intent.payment_failed
- `skipped_event` — status: skipped, event_type: customer.updated
- `charge_refunded_event` — status: pending, event_type: charge.refunded (added in Section 8)

## User fixtures (test/fixtures/users.yml)

- `customer_b2c` — guest: false
- `customer_b2b` — guest: false
- `guest_user` — guest: true
- `admin_user` — role: admin

## Briefing fixtures (test/fixtures/briefings.yml)

- `b2c_briefing` — linked to `b2c_pending` (status: pending), has recipient/mood/occasion
- `b2b_briefing` — linked to `b2b_pending`, minimal fields
- `b2c_paid_briefing` — linked to `b2c_paid_with_stripe` (status: paid), full fields including recipient/mood — added in Section 9
- `b2c_paid_no_optional_briefing` — linked to `b2c_paid` (status: paid), minimal fields (no recipient/mood/occasion) — added in Section 9

## LyricsDraft fixtures (test/fixtures/lyrics_drafts.yml)

- `draft_v1` — order: b2c_paid, version: 1, source: ai_generated
- `draft_v2_regen` — order: b2c_paid, version: 2, source: regenerated, parent: draft_v1
- `draft_approved` — order: b2c_delivered, is_approved: true, is_locked: true
- `draft_lyrics_ready_v1` — order: b2c_lyrics_ready, version: 1, source: ai_generated — use this for regen tests

## Orders useful for LyricsGenerator tests

- `b2c_paid_with_stripe` — status: paid, has `b2c_paid_briefing` — primary fixture for Generator :initial mode
- `b2c_lyrics_ready` — status: lyrics_ready, has `draft_lyrics_ready_v1` — use for Generator :regen mode
- `b2c_lyrics_drafting` — status: lyrics_drafting, has NO briefing by default — use for "no briefing" failure test (call `order.briefing&.destroy` in test setup)

**How to apply:** When writing tests that need specific stripe IDs, either use `update_columns` in setup to inject them onto existing fixtures or use the new stripe-aware fixtures added in Section 8. For LyricsGenerator tests, prefer `b2c_paid_with_stripe` + `b2c_paid_briefing` for initial mode and `b2c_lyrics_ready` + `draft_lyrics_ready_v1` for regen mode.
