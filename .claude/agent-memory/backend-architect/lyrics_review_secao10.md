---
name: lyrics-review-secao10
description: Lyrics review feature (ROADMAP 10) — LyricsApprover, LyricsRegenerator, LyricsController, routes, policy, and test infrastructure for kwargs
type: project
---

# Lyrics Review — Secao 10

693 testes passando apos implementacao.

## Files created/modified

- `app/services/orders/lyrics_approver.rb` — wraps `order.approve_lyrics!` in a transaction with state/draft guards
- `app/services/orders/lyrics_regenerator.rb` — validates regen eligibility, enqueues `GenerateLyricsJob` with kwargs
- `app/controllers/lyrics_controller.rb` — thin controller: authenticate, authorize (`lyrics?`), delegate to services
- `app/jobs/generate_music_job.rb` — stub job enqueued by `lock_lyrics_and_start_music` after lyrics approval
- `app/policies/order_policy.rb` — added `lyrics?`, `approve_lyrics?`, `regenerate_lyrics?` delegating to `show?`
- `app/views/lyrics/` — placeholder views (show.html.erb, _generating.html.erb, _error.html.erb)
- `config/routes.rb` — lyrics routes defined as standalone explicit routes (not nested member) inside brand constraints to get clean named helpers
- `test/test_helper.rb` — `ActiveJobKwargsHelper` module prepended to backport `kwargs:` support to `assert_enqueued_with`

## Key architectural decision: lock_lyrics_and_start_music callback

`Order#lock_lyrics_and_start_music` was originally calling `start_music_generation!` synchronously (transitioning to `music_generating`). Changed to enqueue `GenerateMusicJob.perform_later(id)` instead, so the order stays at `lyrics_approved` after approval. This required updating the order model test that previously asserted `music_generating`.

**Why:** The `LyricsApproverTest` is the authoritative spec for Section 10 and asserts `lyrics_approved` status. Synchronous `start_music_generation!` in the callback conflicted.

**How to apply:** `GenerateMusicJob` is a stub — full Mureka integration is ROADMAP Section 11. Do not add logic to it until then.

## Routes naming

Standalone explicit routes outside `resources` block are necessary to get `order_lyrics_path`, `approve_order_lyrics_path`, `regenerate_order_lyrics_path`. Using `on: :member` inside `resources :orders` appends `_order` suffix, creating unusable helper names. Named helpers defined only in the b2b block; b2c block has the same URLs without `as:`.

**Why:** Rails appends singular resource name to member route helpers. To get `order_lyrics_path` (not `order_lyrics_order_path`), routes must be standalone.

## kwargs: patch for assert_enqueued_with

Rails 8.1 `assert_enqueued_with` does not support `kwargs:`. Added `ActiveJobKwargsHelper` in `test/test_helper.rb` that:
1. Splits deserialized args into positional + trailing kwargs hash (symbol keys)
2. Stringifies the actual kwargs keys before comparing with `hash_including` matchers (WebMock stringifies expected keys internally)
3. Also makes `args: [positional]` matching work when job has trailing kwargs

**Why:** Tests were written expecting `kwargs:` support, which Rails 8.1 lacks. WebMock's `hash_including` stringifies keys but ActiveJob deserializes kwargs with symbol keys — must reconcile.

## application_controller root_path fix

`user_not_authorized` used `root_path` as fallback but no root route exists. Changed to `new_order_path`.
