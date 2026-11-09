---
name: project-chat-interface
description: Plan for the conversational chat interface replacing orders#show — covers BriefingMessage migration, ConversationalBriefingService, OrderChatController, Turbo Stream cards for lyrics/music, and Stimulus controllers needed
metadata:
  type: project
---

The chat interface replaces the static orders/:id show page with a single-page conversational UI after payment. Key decisions:

- New table `briefing_messages` (role, content, extracted_briefing jsonb) — not yet in schema.rb
- `ConversationalBriefingService` calls Anthropic Claude (not Mureka) via the `anthropic` gem
- A `ClaudeClient` wrapper must be created (currently only MurekaLyricsClient exists — no claude_client.rb)
- The existing `LyricsGenerator::Generator` and `GenerateLyricsJob` remain intact but get a new `mode: :chat` or prompt bypass
- Chat action: `POST /orders/:id/chat` → `OrderChatController#create` → Turbo Stream appends
- Cards injected inline as Turbo Stream appends: lyrics_draft_card, music_player_card, download_card
- Turbo channels: `order_#{id}_chat` for async job broadcasts
- Briefing model becomes optional for language/duration only; chat history is the prompt source
- Stimulus controllers needed: `chat-input` (Enter submit, scroll), `lyrics-card` (approve/regenerate inline), `music-card` (player A/B + approve), `download-card`
- AASM states unchanged — only trigger points change (driven from chat actions, not dedicated pages)

**Why:** Replaces multi-page flow with single-page Claude.ai-style chat. ROADMAP item 20 (briefing conversacional) extended to cover the full post-payment lifecycle.

**How to apply:** When planning any order flow changes, remember the chat is the single post-payment hub. The wizard + dedicated /lyrics and /preview pages become legacy (not deleted yet).
