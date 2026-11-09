---
name: project-soundtrack-feature
description: Soundtrack feature plan — Pro-only, SoundtrackInput model, Mureka /v1/soundtrack/generate API, skip-lyrics flow, video upload via ActiveStorage
metadata:
  type: project
---

Soundtrack is a Pro-only feature where a client uploads a short video (Reel/TikTok/ad) and receives that same video with AI-generated music embedded, produced by Mureka's `/v1/soundtrack/generate` endpoint.

**Why:** Differentiates the Pro tier (€59) from Standard. Mureka handles the audio-video merge server-side, so no FFmpeg needed on our end.

**Key architectural decisions:**
- New `soundtrack_inputs` table (per SPEC.md section B.1) — not attached to ActiveStorage on `Order` directly; a separate model to carry Mureka file state and GDPR deletion metadata.
- `input_type` column: `"image"` or `"video"` (SPEC.md uses these values).
- The video upload to R2 happens via the existing upload flow; then `UploadSoundtrackInputToMurekaJob` streams it to Mureka's `/v1/files/upload` endpoint to get a `mureka_file_id`.
- Mureka generate endpoint: `POST /v1/soundtrack/generate` — multipart body with `video_id` (or `image_id`) + `prompt`, `model`, `n`.
- Status polling: new `MurekaStatusClient`-style service `MurekasSoundtrackStatusClient` hitting `/v1/soundtrack/query/{job_id}`. Response shape assumed similar to song/instrumental (choices array), but returns a video URL rather than audio URLs.
- `PollMurekaStatusJob` routing extended to handle `generation_type: "soundtrack"`.
- Pro tier detection: `BRANDS_CONFIG.dig(:b2b, :tiers, :pro, :includes_soundtrack)` — already `true` in SPEC.md.
- Order flow for Pro + video: `paid → music_generating → preview_ready → approved` (skips entire lyrics phase).
- `OrderAsset` gets new kind `"soundtrack_video"` for the delivered video.
- GDPR: `scheduled_deletion_at` set 30 days after delivery; `DeleteSoundtrackInputJob` handles cleanup.

**How to apply:** When planning any task touching the Pro tier, music generation pipeline, or order status machine, verify compatibility with this parallel flow.
