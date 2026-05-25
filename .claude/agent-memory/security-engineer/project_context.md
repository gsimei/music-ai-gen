---
name: project-context
description: Music AI Gen project overview — multi-brand Rails 8.1 SaaS, B2B/B2C, GDPR-applicable (European market)
metadata:
  type: project
---

Music AI Gen is a Rails 8.1 multi-brand B2B/B2C SaaS for AI-generated music, targeting the European market (GDPR applicable).

Two brands: JinglePro (B2B, jinglepro.it/com) and MusicaRegalo (B2C, musicaregalo.it/com).

Core stack: Ruby on Rails 8.1, PostgreSQL 16, Hotwire (Turbo + Stimulus), Tailwind CSS, ViewComponent, Solid Queue, Kamal 2 deploy.

Key integrations (upcoming): Stripe for payments, Anthropic/Claude for lyrics generation, Mureka API for music generation, Cloudflare R2 for storage, Postmark for email.

**Why:** European market means GDPR compliance is a hard requirement, not optional.

**How to apply:** Always flag GDPR implications (data minimization, PII in logs/errors, consent flows, data retention) in security reviews.
