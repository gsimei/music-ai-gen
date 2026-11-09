---
name: project-orders-show-patterns
description: Orders#show hub implementation patterns — Turbo Stream targets, state machine display, brand-aware partials
metadata:
  type: project
---

# orders#show Single-Page Hub Patterns

## Turbo Stream target IDs (must never be renamed)
- `lyrics_section` — outer wrapper for `_lyrics_section.html.erb`, replaced by turbo_stream on state change
- `music_section` — outer wrapper for `_music_section.html.erb`
- `lyrics_content` — inner region for draft content, replaced independently on regen
- `lyrics_generating_notice` — inner region for wave-bar animation, replaced on regen submit
- `lyrics_errors` — empty initially, replaced by `_lyrics_errors.html.erb` on failure
- `music_section_errors` — empty initially, replaced by `_music_section_errors.html.erb` on failure

## Brand local variable convention
All partials receive `brand:` as a boolean (`true` = b2b) from show.html.erb:
```erb
render "orders/lyrics_section", order: @order, draft: @draft, brand: current_brand == "b2b"
```
Inside partials the convention is: `<% b2b = brand == true || brand == "b2b" %>` to handle both boolean and string.

## Route helpers for orders actions
- `approve_lyrics_order_path(order)` — POST to `orders#approve_lyrics`
- `regenerate_lyrics_order_path(order)` — POST to `orders#regenerate_lyrics`
- `approve_music_order_path(order)` — POST to `orders#approve_music`
- `regenerate_music_order_path(order)` — POST to `orders#regenerate_music`
- `checkout_order_path(order)` — POST to `orders#checkout` (with `data: { turbo: false }`)

## AASM state display groups
| Display states | What shows |
|---|---|
| `pending`, `payment_failed` | Payment CTA in lyrics_section; music_section hidden |
| `paid`, `lyrics_drafting` | Wave-bar generating animation; music_section hidden |
| `lyrics_ready` | Draft text + approve/regen buttons; music_section hidden |
| `lyrics_approved`, `music_generating` | Read-only approved lyrics; music_section shows generating animation |
| `preview_ready` | Read-only approved lyrics; music_section shows A/B variant cards |
| `approved` | Read-only approved lyrics; music_section shows approved variant + songs_path CTA |
| `lyrics_failed` | Error card in lyrics_section |
| `music_failed` | Error card in music_section |

## Stimulus controllers used
- `lyrics-review` — targets: `feedbackForm`, `adjustButton`. Actions: `showFeedback`, `hideFeedback`
- `music-regen` — targets: `regenForm`, `toggleButton`. Actions: `showForm`, `hideForm`

## Wave animation pattern
Five bars with staggered durations using inline style:
```erb
<% [1.02, 1.18, 1.34, 1.18, 1.02].each_with_index do |d, i| %>
  <div class="w-0.5 rounded-full <%= b2b ? 'bg-cant-brass' : 'bg-ser-blush' %>"
       style="height: 100%; transform-origin: center;
              animation: wave-rise <%= d %>s ease-in-out <%= i * 0.08 %>s infinite;"></div>
<% end %>
```
`wave-rise` keyframe is defined in `app/assets/tailwind/application.css`.

## Dark generating card pattern
```erb
<div class="<%= b2b ? 'bg-cant-ink text-cant-paper rounded-sm' : 'bg-ser-ink text-ser-cream rounded-2xl' %>
            min-h-[80px] px-5 py-5 flex flex-col justify-center relative overflow-hidden">
  <div class="absolute inset-0 pointer-events-none"
       style="background: radial-gradient(circle at 70% 50%,
                <%= b2b ? 'oklch(0.72 0.13 75)' : 'oklch(0.82 0.07 40)' %> 0%,
                transparent 65%); opacity: 0.15;"
       aria-hidden="true"></div>
  ...wave bars...
</div>
```

## wizard/step_3 — structure_hint field
Already implemented. Field: `order_wizard[structure_hint]`, id: `wizard_structure_hint`, optional, rows: 2.

**Why:** [[project-wizard-patterns]]
