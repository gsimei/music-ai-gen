---
name: b2b-only-migration
description: B2B-only migration completed — removed all b2c code, fixtures, and tests; 813 tests passing
metadata:
  type: project
---

Platform migrated to exclusively B2B. All b2c code removed.

**Why:** Business pivot — focus on B2B jingles for social media, dropping the B2C gift music concept.

**How to apply:** There is no longer any b2c branch in the codebase. Brand detection always returns :b2b. Never re-introduce b2c conditionals.

## Key decisions made

- `customer_b2c` user fixture removed; replaced by `customer_b2b` (the canonical test customer)
- Added `customer_other` user fixture for "different user" authorization tests — tests that check a user can't access another user's order now sign in as `customer_other`
- Former `b2c_*` order fixtures renamed `b2b_*` (14 fixtures); former standalone `b2b_pending` renamed `b2b_pending_2`
- `b2b_paid_briefing` fixture has `target_duration_seconds: 120`, `recipient: "Maria"`, `mood: "happy"`, `occasion: "birthday"` — required by LyricsGenerator::PromptBuilder tests that assert long-form prompt structure (>60s enables structure_hint branch)
- `b2b_paid_no_optional_briefing` fixture has nil optional fields — used by tests checking no "nil" interpolation in prompt

## State after migration

- 813 tests, 0 failures, 0 errors
- `grep -rn "\bb2c\b" app/ config/` → 0 results
- `grep -rn "ser-" app/views app/javascript` → 0 results
- `BrandLocaleResolver#detect_brand` always returns `:b2b` (host-based detection removed)
- `Order::BRANDS`, `User::BRANDS`, `Voice::VALID_BRANDS` all `%w[b2b].freeze`

## Files changed (key)

- `test/fixtures/orders.yml` — 14 b2c_ fixtures renamed to b2b_; b2b_pending → b2b_pending_2
- `test/fixtures/users.yml` — removed customer_b2c; added customer_other
- `test/fixtures/briefings.yml` — renamed all b2c_ fixtures; b2b_paid_briefing has full optional fields
- All test/*.rb — global replace of orders(:b2c_*), users(:customer_b2c), host! "b2c.lvh.me"
