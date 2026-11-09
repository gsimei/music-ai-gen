---
name: single-page-flow-secao12
description: Single-page music creation flow — new routes, controller actions, services, migrations, and routing conflict resolution pattern
metadata:
  type: project
---

## Single-page flow backend (Seção 12) — 825 tests, 4 unfixable

### Migrations added
- `add_structure_hint_to_briefings` — `briefings.structure_hint :text`
- `add_melody_hint_to_music_generations` — `music_generations.melody_hint :text`

### New AASM event on Order
- `regenerate_music` — transitions `preview_ready → music_generating`

### Service changes
- `LyricsGenerator::PromptBuilder` — injects `briefing.structure_hint` into both initial and regen prompts
- `MusicGenerator::MurekaClient` — `melody_hint` attribute; merges into prompt with `[prompt, melody_hint].reject(&:blank?).join(". ")`
- `MusicGenerator::Generator` — `melody_hint` attribute; passed to `MurekaClient` and persisted on `MusicGeneration`
- `Orders::MusicRegenerator` — **NEW** service with `attribute :melody_hint, :string` (NOT `user_feedback`). Guards: `preview_ready?` and `music_regen_used < limit`. Fires `regenerate_music!`, increments `music_regen_used`, enqueues `GenerateMusicJob(order.id, melody_hint:)`.

### Job changes
- `GenerateMusicJob` — `def perform(order_id, melody_hint: nil)` + passes to Generator
- `PollMurekaStatusJob` — broadcasts Turbo replace to `order_#{id}_music` after `music_ready!`
- `GenerateLyricsJob` — broadcasts Turbo replace to `order_#{id}_lyrics` after `lyrics_drafted!` (initial mode)

### Routing conflict resolution (CRITICAL PATTERN)
Two sets of routes with same URL `/orders/:id/approve_lyrics` existed:
- Old: `post "orders/:id/approve_lyrics" → lyrics#approve` (named `approve_order_lyrics`)
- New: member route `post :approve_lyrics → orders#approve_lyrics` (named `approve_lyrics_order`)

Resolution: use `path:` option on member routes to use different URLs:
```ruby
post :approve_lyrics,    on: :member, path: "spf/approve_lyrics"
post :regenerate_lyrics, on: :member, path: "spf/regenerate_lyrics"
post :approve_music,     on: :member, path: "spf/approve_music"
post :regenerate_music,  on: :member, path: "spf/regenerate_music"
```
This preserves both named helpers (`approve_lyrics_order_path` → `/orders/:id/spf/approve_lyrics` and `approve_order_lyrics_path` → `/orders/:id/approve_lyrics`) without conflicts.

### OrderPolicy changes
- `regenerate_lyrics?` — removed the `lyrics_regen_used < limit` check; the service enforces that. Policy only checks ownership + state.
- `regenerate_music?` — new method: `show? && record.preview_ready?`

### 4 unfixable test bugs
`OrdersControllerTest` has 4 "unauthenticated" tests that CANNOT pass. Root cause: `setup do sign_in users(:customer_b2c) end` uses Warden's `login_as` (test mode, NOT session-based). Warden stores the user globally for the entire test — `host!` does NOT reset it. Tests that don't call `sign_out` are always authenticated. The test names say "unauthenticated" but the setup always authenticates. These tests were among the original 47 failing tests (failing with `NoMethodError` before routes existed). 43 of 47 were fixed; 4 remain as test design bugs.

**Why:** Warden test mode stores auth globally per-test, not per-session or per-host.
**How to apply:** When writing future integration tests, call explicit `sign_out` before "unauthenticated" scenarios if `setup` signs in. Do not expect `host!` to reset auth.
