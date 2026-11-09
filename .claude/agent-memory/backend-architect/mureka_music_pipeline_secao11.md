---
name: mureka-music-pipeline-secao11
description: Mureka music generation pipeline — MurekaClient, MurekaStatusClient, Generator, GenerateMusicJob, PollMurekaStatusJob; 788 tests passing
metadata:
  type: project
---

# Mureka Music Generation Pipeline (Seção 11)

788 tests passing after this section. Added 93 new tests.

## Migration decisions

Two migrations added:
- `20260526120000`: adds `mureka_job_id` (string), `poll_count` (integer default 0 NOT NULL), `model` (string) to `music_generations`; adds `variant_index`, `provider_url`, `flac_url`, `wav_url`, `duration_ms` to `order_assets`
- `20260526120001`: makes `order_assets.storage_key` nullable — required because `music_variant` assets have no storage_key (they reference provider URLs, not ActiveStorage)

**Why storage_key is nullable**: `music_variant` assets are created by `PollMurekaStatusJob` directly from Mureka CDN URLs. They are not uploaded to our storage. The existing `NOT NULL` constraint on `storage_key` had to be relaxed.

## OrderAsset KINDS pattern

`KINDS = %w[final_mp3 final_wav stems_zip lyrics_pdf].freeze` — kept unchanged to avoid breaking existing tests.
`PROVIDER_KINDS = %w[music_variant].freeze` — new constant for provider-managed assets.
`ALL_KINDS = (KINDS + PROVIDER_KINDS).freeze` — used for inclusion validation.

**Why**: An existing test asserts `KINDS` equals exactly 4 values. Adding `music_variant` to `KINDS` would break it. The split allows both old and new tests to pass.

## Service architecture

`MusicGenerator::MurekaClient` — POST to `/v1/song/generate`; omits `voice_id` key entirely if blank; maps `id` → `job_id`.

`MusicGenerator::MurekaStatusClient` — GET `/v1/song/query/:job_id`; maps Mureka `duration` field → `duration_ms` in choices; treats `pending` and any unknown status as pending.

`MusicGenerator::Generator` — guards in order: `lyrics_approved?` → `current_draft` → `briefing` → `briefing.voice_id`. Passes `briefing.voice.external_id` as `voice_id` to MurekaClient (NOT the FK integer). Sets `model: "auto"` on MusicGeneration. Calculates `next_iteration` from `order.music_generations.maximum(:iteration)`.

## Job design

`GenerateMusicJob` — calls `start_music_generation!` first, then `Generator.call`. On Generator failure calls `fail_music!`. Rescues `AASM::InvalidTransition` from both transitions gracefully. Does NOT use `discard_on` / `retry_on` so that `RecordNotFound` propagates naturally (test requirement).

`PollMurekaStatusJob` — `MAX_POLLS = 40`, `POLL_INTERVAL = 15.seconds`, queue `:default`. Increments `poll_count` BEFORE the case branch (so poll_count 40 triggers timeout). Uses `update_columns` to update `music_generation.status` (avoids callback overhead). Wraps `fail_music!` and `music_ready!` in `AASM::InvalidTransition` rescue blocks.

## Fixture decisions

`generation_pending` fixture moved to use `b2c_music_generating` order (status: `music_generating`) so that `fail_music!` AASM transition works in poll tests. Added `generation_paid_iter1` fixture to `b2c_paid` to preserve the uniqueness constraint test in `music_generation_test.rb`.

Added `draft_music_generating_v1` (approved, locked) as lyrics_draft for `b2c_music_generating` order. Added `draft_lyrics_approved_v1` for `b2c_lyrics_approved` order.

Added `b2c_lyrics_approved_briefing` with `voice: standard_voice` to briefings.yml.

## Gem added

`climate_control ~> 1.0` added to `:test` group — required by `mureka_client_test.rb` and `mureka_status_client_test.rb` for `ClimateControl.modify(MUREKA_API_KEY: ...)` blocks.
