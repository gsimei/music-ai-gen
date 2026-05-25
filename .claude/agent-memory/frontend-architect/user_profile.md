---
name: user-profile
description: Developer profile — building a multi-brand music AI platform (Rails 8, Hotwire, Tailwind 4)
metadata:
  type: user
---

# User Profile

**Project:** Music AI Gen — multi-brand platform for AI-generated music (JinglePro B2B, MusicaRegalo B2C)

**Stack expertise:** Rails 8, Hotwire (Turbo + Stimulus), Tailwind CSS 4, ViewComponent, PostgreSQL, Stripe, Anthropic Claude API, Kamal deploy.

**Working style:** Follows a strict agent workflow (idea-validator → task-planner → tdd-architect → backend/frontend-architect → minitest-runner). Frontend work always has a design reference (Plataforma - Vanilla.html at project root) that must be consulted before any view implementation.

**Market:** Europe, primarily Italy. Multi-language (it, en, es, fr, de, pt). Italian is the default and primary locale.

**Brand architecture:** Two brands share one backend. Brand detection by HTTP host. All price/limit config in `config/brands.yml` — never hardcoded. `current_brand` available in all controllers/views via `around_action`.
