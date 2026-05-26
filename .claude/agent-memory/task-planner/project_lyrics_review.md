---
name: project-lyrics-review
description: Implementation plan for ROADMAP item 10 — lyrics review UI at /orders/:id/lyrics with approve and regenerate endpoints
metadata:
  type: project
---

Lyrics review UI (ROADMAP item 10) planned 2026-05-26.

Key decisions:
- Two new member routes inside BrandConstraint blocks: GET lyrics, POST approve_lyrics, POST lyrics/regenerate
- LyricsController (separate from OrdersController) handles the three actions
- Service: Orders::LyricsApprover (approve path) reuses AASM event with current_lyrics_draft_id virtual attr
- Service: Orders::LyricsRegenerator (regen path) increments regen_used, enqueues GenerateLyricsJob mode:"regen"
- Turbo Stream broadcast from GenerateLyricsJob after regen completes, targeting dom_id "lyrics_content"
- Stimulus controller: lyrics-review — toggles feedback form, submits regen via Turbo form
- No ViewComponent for now — plain ERB (ViewComponent not installed)
- Fixtures needed: b2c_lyrics_ready_at_limit (lyrics_regen_used == lyrics_regen_limit)

**Why:** ViewComponent is NOT in the Gemfile — plan uses plain ERB partials.
**How to apply:** Do not propose ViewComponent for any views in this project until gem is added.
