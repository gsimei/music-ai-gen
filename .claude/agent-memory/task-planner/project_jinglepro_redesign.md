---
name: project-jinglepro-redesign
description: Plan 2026-11-09 for porting the JinglePro canvas redesign to Rails (slices 0-5) with verified code seams and gotchas
metadata:
  type: project
---

Redesign "JinglePro" (canvas .dc.html boards, scratchpad of session 930c05d4) planned in slices: 0 baseline commit + doc sync; 1 tokens/CSS/landing/auth/library; 2 Criar reskin; 3 Estudio 3 phases + Entrega; 4 auth inversion + pay in step 3 (security-engineer mandatory); 5 dead chat code removal.

Verified seams (non-obvious from reading one file):
- Criar is already ONE `<form>` with client-side steps (`campaign_form_controller`); sessionStorage not needed up front.
- All async jobs call `OrderChatBroadcaster` (targets `chat-workflow`, `chat-lyrics-panel`): single seam to retarget in slice 3. `creative_editor_controller` guards unsaved edits by matching target name `chat-lyrics-panel`; renaming without updating it silently drops edit protection.
- Tailwind `cant-*` classes live in legacy views AND `order_chat/*` partials, so Tailwind build can only go after slice 3; `studio*.css` serve Criar/Estudio/Entrega until then (dual CSS, prefixes `jp-` vs `studio-`/`campaign-`).
- `OrdersController#show` uses unscoped `Order.find` (authenticated IDOR); legacy removal closes it.
- Tests couple to CSS classes (~11 asserts, 6 files): first refactor to semantic selectors, then restyle.
- `_sound_fields` partial is shared by Criar and Estudio; `select` -> radios breaks 3 integration tests.
- Canvas cannot render outside the canvas (no support.js, `/_blob` images): need PNG exports in `design/jinglepro/`; Playwright compares computed styles + side-by-side, not pixel-diff.
- Hardcoded canvas values must come from: `campaign_price`, `Campaigns::MusicRounds::LIMIT`, `brands.yml tiers.starter.lyrics_regen_limit`, audio metadata duration (max `Campaigns::AudioPreview::MAX_DURATION`=30).
- Production gaps before real money: force_ssl/assume_ssl commented, storage :local, empty CSP, no rate_limit anywhere.

**Why:** user wants the redesign delivered incrementally with approval stops; validator already fixed scope (visual-only vs flow-changing).
**How to apply:** when asked to refine/execute any slice, start from these seams instead of re-auditing; check whether user answered the pending decisions (baseline commit OK, prod legacy-order count, duplicate-email option A/B, legal text, PNG exports, mobile boards).
