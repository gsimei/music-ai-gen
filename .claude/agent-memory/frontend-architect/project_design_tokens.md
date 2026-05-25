---
name: project-design-tokens
description: Tailwind CSS 4 design tokens for cant-* (B2B/JinglePro) and ser-* (B2C/MusicaRegalo) palettes
metadata:
  type: project
---

# Design Tokens — Music AI Gen

Defined in `app/assets/tailwind/application.css` using `@theme {}` block (Tailwind 4 approach — no tailwind.config.js).

## B2B — Cantabile / JinglePro (forest palette)
- `--color-cant-ink`   = `oklch(0.22 0.04 155)` — dark forest green, primary text/backgrounds
- `--color-cant-paper` = `oklch(0.97 0.012 80)` — warm ivory, page background
- `--color-cant-brass` = `oklch(0.72 0.13 75)`  — gold/brass accent (CTAs, highlights)
- `--color-cant-mute`  = `oklch(0.58 0.02 145)` — muted text
- `--color-cant-line`  = `oklch(0.85 0.012 80)` — dividers/borders

Fonts: `--font-cant-display` (Cormorant Garamond), `--font-cant-body` (Manrope)

## B2C — Serenata / MusicaRegalo (blush/bordeaux palette)
- `--color-ser-cream`  = `oklch(0.96 0.025 70)` — warm cream, page background
- `--color-ser-ink`    = `oklch(0.32 0.13 25)`  — bordeaux, primary text/backgrounds
- `--color-ser-blush`  = `oklch(0.82 0.07 40)`  — blush pink accent
- `--color-ser-shadow` = `oklch(0.50 0.14 25)`  — darker bordeaux for badges/accents
- `--color-ser-mute`   = `oklch(0.52 0.08 25)`  — muted text
- `--color-ser-line`   = `oklch(0.88 0.04 40)`  — dividers/borders

Fonts: `--font-ser-display` (Instrument Serif), `--font-ser-body` (Geist)

## Usage in ERB
```erb
<% b2b = current_brand == "b2b" %>
<div class="<%= b2b ? 'bg-cant-paper text-cant-ink font-cant-body' : 'bg-ser-cream text-ser-ink font-ser-body' %>">
```

**Why:** The prototype (Plataforma - Vanilla.html) uses these exact OKLCH values. Replicated as CSS custom properties rather than arbitrary values to allow reuse across components.

**How to apply:** Always detect brand with `current_brand == "b2b"` and branch classes accordingly. Never hardcode colors — always use the token variables.
