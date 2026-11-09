---
name: project-music-creation-flow-redesign
description: Plan for redesigned single-page post-payment flow + structure_hint + music regen — approved 2026-05-27
metadata:
  type: project
---

Redesign of post-payment experience: orders#show becomes the single hub for lyrics review, music preview and both approval actions. Also adds `structure_hint` to briefing and `melody_hint` to music_generations, plus a new `Orders::MusicRegenerator` service.

**Why:** Better UX — no page redirects between lyrics/music phases. All state changes broadcast via Turbo Streams from the jobs that already exist.

**How to apply:** When planning related work (Turbo broadcasts, new Order actions, briefing fields) refer to this plan for already-decided controller/route structure.

Key decisions made:
- New actions (`approve_lyrics`, `regenerate_lyrics`, `approve_music`, `regenerate_music`) go on `OrdersController`, NOT a new separate controller
- Old `LyricsController` and `MusicPreviewController` routes are kept but deprecated (kept for backward compat)
- `structure_hint` added to `briefings` table (nullable text)
- `melody_hint` added to `music_generations` table (nullable text)
- Wizard: `structure_hint` added to Step 3 (the optional/details step), not Step 2 (already dense with required fields)
- New service `Orders::MusicRegenerator` parallels `Orders::LyricsRegenerator`
- Two new Turbo broadcast stream identifiers: `order_#{id}_lyrics` (already exists in GenerateLyricsJob) and `order_#{id}_music` (new, broadcast from PollMurekaStatusJob)
- `orders#show` subscribes to both streams via `turbo_stream_from`
- Partials `orders/_lyrics_section` and `orders/_music_section` replace existing sectional views
