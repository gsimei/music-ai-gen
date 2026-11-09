---
name: soundtrack-feature
description: Soundtrack feature implementation — pro-tier video/image upload with AI music merge, bypassing lyrics phase
metadata:
  type: project
---

## Soundtrack Feature — Implementation (2026-05-30)

Pro-tier orders can bypass the entire lyrics phase and go directly from `paid` → `music_generating` by uploading a video or image file.

### Schema additions
- `soundtrack_inputs` table: `order_id` (unique FK), `input_type` (image/video), `storage_key`, `mureka_file_id`, `mureka_file_status` (pending/ready/failed), plus metadata columns. Unique index on `order_id` — one input per order.
- `music_generations.generation_type` column: `NOT NULL, default "song"`, values: `song`, `instrumental`, `soundtrack`.

### Key design decisions

**`t.references` + `add_index` conflict**: When using `t.references :order, null: false, foreign_key: true` in a migration, Rails auto-creates a non-unique index on `order_id`. Adding a separate `add_index :soundtrack_inputs, :order_id, unique: true` will fail with "relation already exists". Fix: use `t.references :order, null: false, foreign_key: true, index: false` and let the explicit `add_index` create the unique one.

**AASM `enqueue_post_payment_generation` callback**: `mark_paid` callback was renamed from `enqueue_lyrics_generation` to `enqueue_post_payment_generation` which branches: if `soundtrack_order?` → `UploadSoundtrackInputToMurekaJob`, else → `GenerateLyricsJob`. Original `enqueue_lyrics_generation` method kept for backward compat (still used by tests checking direct enqueue).

**`order.soundtrack_order?` predicate**: checks `tier_config&.dig(:includes_soundtrack) && soundtrack_input.present?`. Both conditions must be true — tier flag alone is insufficient.

**`config/brands.yml`**: Added `includes_soundtrack: false` to `starter`, `includes_soundtrack: true` to `pro`.

**`PollMurekaStatusJob` routing**: Replaced instrumental boolean flag from `briefing.extra_params` with `music_gen.generation_type` case statement. Cleaner, fully typed. Soundtrack type calls `MurekaSoundtrackStatusClient` and `create_soundtrack_asset` (creates single `soundtrack_video` asset, not A/B variants).

**`OrderAsset` validation**: `storage_key` presence skipped using lambda `unless: -> { music_variant? || soundtrack_video? }` — both provider-sourced kinds have no local storage key.

**Multipart upload in `MurekaFilesUploadClient`**: Pure `Net::HTTP` multipart with manual boundary construction. Reads file via `File.binread`, builds body as `ASCII-8BIT` string. No gems added.

**`MurekaSoundtrackClient`**: request body key depends on `input_type` — `video_id` for video, `image_id` for image.

**`MurekaSoundtrackStatusClient`**: identical to `MurekaInstrumentalStatusClient` but `map_choices` returns only `{url:, duration_ms:}` — no `lyrics_sections`, no `flac_url`/`wav_url`.

**Job chain**: `UploadSoundtrackInputToMurekaJob` → on success → `GenerateSoundtrackJob` → `Generator#call_soundtrack` → `PollMurekaStatusJob`.

**`show.html.erb` branch**: Soundtrack orders render `_soundtrack_section` partial instead of lyrics + music sections.

**Route nesting**: `resource :soundtrack_input, only: %i[new create], path: "soundtrack"` nested inside `resources :orders` block. Path helper: `order_soundtrack_input_path(order_id: order.id)`.

### Test count: 889 passing (76 new tests)

**Why:** Pro-tier users wanting to add music to existing media don't need AI lyrics — the flow should be direct and simple.

**How to apply:** When adding future media-processing features that bypass the lyrics phase, follow this same AASM branch-in-callback pattern and `generation_type` routing in PollMurekaStatusJob.
