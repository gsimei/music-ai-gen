---
name: project-wizard-patterns
description: Turbo Frame + Stimulus patterns established for the briefing wizard (orders/wizard steps 1-5)
metadata:
  type: project
---

# Wizard Implementation Patterns

## Turbo Frame Structure
Each step view (`app/views/orders/wizard/step_N.html.erb`) is wrapped in `turbo_frame_tag "wizard"`. The outer shell `orders/new.html.erb` redirects to step 1 via the controller. No turbo_frame outer shell view needed — the controller redirects directly.

## Controller Variables Available in Step Views
- `@step` — current step number (Integer)
- `@wizard_session` — `Orders::WizardSession` instance; call `.to_h` for saved data
- `@validator` — `Orders::StepValidator` instance, only present on validation failure (422)
- `@voices` — `Voice::ActiveRecord_Relation`, available in steps 4 and 5 (added via `load_step_resources`)
- `@brand_config` — `BRANDS_CONFIG[brand.to_sym]`, available in step 5

## Accessing Saved Data
```erb
<% saved = @wizard_session&.to_h || {} %>
<% saved[:delivery_email] %>
```

## Error Display Pattern
```erb
<% if @validator&.errors&.include?(:field_name) %>
  <p id="field-error" role="alert" class="mt-1.5 text-xs text-red-600">
    <%= @validator.errors[:field_name].first %>
  </p>
<% end %>
```
With `aria-invalid` and `aria-describedby` on the input pointing to the error id.

## Stimulus Controllers
- `wizard-voice` — manages voice card selection in step 4; dispatches `wizard-voice:selected` on window with `{ voiceId, proOnly }`
- `wizard-tier`  — manages tier selection in step 5; listens for `wizard-voice:selected` to enforce pro-only constraint

## Cross-Controller Communication
`wizard-voice` dispatches `wizard-voice:selected` on `window`. `wizard-tier` listens with `window.addEventListener`. This decouples the two controllers and works across Turbo Frame navigations.

**Why:** The pro-voice → pro-tier constraint must be enforced client-side without a page reload when the user navigates back to step 4 and changes their voice selection.
