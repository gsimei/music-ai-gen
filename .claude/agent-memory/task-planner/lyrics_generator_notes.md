---
name: lyrics-generator-notes
description: Architecture decisions and key facts about the LyricsGenerator pipeline (Item 9) — Claude-only mode, prompt versioning, GenerationJob log pattern, AASM hooks
metadata:
  type: project
---

## Decision: Claude-only pipeline (Mureka skipped for lyrics)

`LyricsGenerator::MurekaLyricsClient` exists as an empty stub. The `Generator` is driven by a
`use_mureka` flag (default `false`). When `false`, `Generator` calls `ClaudeClient` directly with
`INITIAL_PROMPT` (no refine step). When `true` (future), it calls Mureka first, then uses
`REFINE_PROMPT` to pass the raw Mureka draft to Claude. Decision recorded in SPEC 13.1.

## Prompt versioning

Constants live in `LyricsGenerator::PromptBuilder`:
- `PROMPT_VERSION = "v1.0"` — bumped manually to `"v1.1"`, `"v2.0"`, etc. on any template change
- Stored in `lyrics_drafts.prompt_version` and `generation_jobs.prompt_version`

Three prompt templates:
- `INITIAL_PROMPT` — full briefing → JSON structured lyrics (direct Claude, no Mureka draft)
- `REFINE_PROMPT` — Mureka raw draft + full briefing → JSON structured lyrics (used only if use_mureka)
- `REGEN_PROMPT` — current lyrics text + user_feedback + briefing → JSON structured lyrics

## GenerationJob log pattern

One `GenerationJob` row per API call:
- step: `"lyrics_initial"` (initial generation) or `"lyrics_regen"` (regeneration)
- provider: `"anthropic"`
- model: `"claude-opus-4-7"`
- `started_at` set before API call, `finished_at` after, `latency_ms` computed
- `request_payload` stores prompt text (sanitised/truncated if needed)
- `response_payload` stores raw Claude response
- `input_tokens`, `output_tokens`, `total_tokens`, `cost_usd` populated from Claude usage metadata
- `lyrics_draft_id` set after the draft is persisted (so a failed call has nil `lyrics_draft_id`)
- status: `"pending"` → `"success"` or `"failed"`

## AASM transitions triggered by GenerateLyricsJob

Success path:
1. `order.start_lyrics_generation!` (paid → lyrics_drafting) — called at job start
2. Draft persisted
3. `order.lyrics_drafted!` (lyrics_drafting → lyrics_ready) — triggers `OrderMailer.lyrics_ready`

Failure path (after retries exhausted):
- `order.fail_lyrics!` (lyrics_drafting → lyrics_failed) — triggers `notify_admin`

## GenerateLyricsJob parameters

`perform(order_id, mode: "initial", parent_draft_id: nil, user_feedback: nil)`
- `mode: "initial"` → calls Generator in initial mode
- `mode: "regen"` → requires `parent_draft_id` and `user_feedback`, calls Generator in regen mode
- Retry: Solid Queue exponential backoff, max 5 attempts; after exhaustion calls `order.fail_lyrics!`

## Version increment for next draft

`LyricsDraft.version` = `order.lyrics_drafts.maximum(:version).to_i + 1`
Computed inside `Generator#call`, not in the job.

**How to apply:** When implementing or updating this pipeline, always log one GenerationJob per API
call (not per job run), store prompt/response payloads, and update AASM through events rather than
direct status writes. See [[stripe-integration-notes]] for the `requires_new_transaction: false`
AASM caveat.
