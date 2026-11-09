---
name: fixture-preview-ready-briefing
description: b2c_preview_ready order fixture lacked a briefing fixture — needed one for MusicRegenerator and controller tests
metadata:
  type: feedback
---

The `b2c_preview_ready` order fixture existed in `orders.yml` but had no corresponding entry in `briefings.yml`. Tests exercising music regeneration on a `preview_ready` order will fail with `nil` briefing unless `b2c_preview_ready_briefing` is added. Same for any "at_limit" variant.

**Why:** The fixture relationship is not enforced at DB level in test mode — it's a silent nil until something calls `.briefing`.

**How to apply:** Whenever adding a new order fixture for a state that exercises music generation (music_generating, preview_ready), always add a corresponding briefing fixture with a voice association.
