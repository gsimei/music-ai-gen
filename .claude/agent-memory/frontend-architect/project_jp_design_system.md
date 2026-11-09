---
name: project-jp-design-system
description: JinglePro design system integration — CSS aliases, JS assets, layout conventions, and component classes
metadata:
  type: project
---

The JinglePro design system (from `jinglepro/jp-styles.css`) is fully integrated into `app/assets/tailwind/application.css`. Key conventions:

**CSS alias variables (after @theme block):**
- `--ink`, `--paper`, `--brass`, `--mute`, `--line` map to `--color-cant-*` Tailwind tokens
- `--sans`, `--display` map to `--font-cant-*` tokens
- `--ease`, `--ease-out` are cubic-bezier values

**Component classes to use instead of raw Tailwind:**
- `.wrap` — max-width 1180px container with responsive padding (not `max-w-7xl mx-auto px-6`)
- `.btn .btn-primary/.btn-secondary/.btn-accent/.btn-paper-outline` — pill-shaped buttons
- `.btn-block`, `.btn-sm` — button modifiers
- `.card`, `.card-ink` — border-radius 2px cards (paper or ink background)
- `.pill`, `.pill.on`, `.pill.lg` — selection pills (also work with native radio inputs via `:has()`)
- `.lang`, `.lang.on` — language selector cards (native radio support via `:has()`)
- `.badge-brass`, `.badge-amber`, `.badge-line`, `.badge-brassline` — status badges
- `.reveal` + `.seen` — scroll-reveal animation (triggered by jp_motion.js IntersectionObserver)
- `.display` — Cormorant Garamond wrapper class
- `.eyebrow` — brass uppercase label style
- `.mag` — magnetic button wrapper (requires GSAP)
- `.grain` — film grain fixed overlay (in layout body)
- `.loadcard`, `.wavebars` — loading states for music/lyrics generation
- `.player.on-ink` + `.wf[data-seed]` — decorative waveform player (drawn by jp_motion.js)
- `.auth .left / .right` — 40/60 split auth layout
- `.wzbar`, `.progress`, `.pstep.active/.done`, `.wzhead`, `.wzbody`, `.wzfoot.between` — wizard layout
- `.orderhead`, `.biz`, `.ref`, `.summary-tags` — order page header
- `.lib-card` — library song card
- `.empty .eic` — empty state with icon
- `.testi`, `.testi .who`, `.testi .av` — testimonial cards
- `.tiers` — 2-column tier grid (max-width 680px)
- `.tier`, `.tier-ink`, `.tier.selectable`, `.tier.sel` — pricing tier cards
- `.voice`, `.voice.sel`, `.vname`, `.vtags`, `.vtag`, `.vbars` — voice selector cards

**JS assets:**
- `app/javascript/jp_waveform.js` — hero canvas player (requires `<canvas id="heroWave">` inside `.hero-player`)
- `app/javascript/jp_motion.js` — reveals, wirePlayers(), wirePills(), wireTiers(), wireLyrics(), wireMagnetic(), count-up; re-wired on `turbo:load`
- Both pinned in `config/importmap.rb` as `jp_waveform` and `jp_motion`
- Imported in `application.js` as `import "jp_waveform"` / `import "jp_motion"`
- GSAP CDN loaded in layout `<head>` with `defer`

**Layout:**
- `<div class="grain" aria-hidden="true">` added as first element inside `<body>` in application layout
- Pages no longer use `min-h-screen` wrapper div — `.wrap` or `.auth` handles container

**Pill/lang `:has()` CSS fallback:**
- `.pill:has(input:checked)` and `.lang:has(input:checked)` in CSS for progressive enhancement without JS

**Why:** Visual unification across all pages with the editorial/artisanal premium design from the JinglePro prototype.
