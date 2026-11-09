---
name: project-chat-mode-patterns
description: Chat mode tab pattern for Pro-tier order chat — Stimulus controller, form multipart, soundtrack upload flow
metadata:
  type: project
---

## Chat mode tabs (Soundtrack feature, Pro tier only)

The order chat has a two-tab mode switcher ("Music" / "Soundtrack") that is only rendered when `order.tier_config&.dig(:includes_soundtrack)` is true. In `brands.yml` the `pro` tier has `includes_soundtrack: true`; the `starter` tier has it as `false`.

**Why:** The soundtrack flow requires a file upload (video/image) and bypasses the lyrics generation pipeline entirely, going straight to `UploadSoundtrackInputToMurekaJob`. The tab UI gates this input at the view layer.

### Key files
- Partial: `app/views/order_chat/_chat_tabs.html.erb`
- Stimulus: `app/javascript/controllers/chat_mode_controller.js`
- Controller: `app/controllers/order_chat_controller.rb` — `create` action branches on `params[:mode]` and `params[:file]`

### Controller structure (`create`)
- `mode == "soundtrack" && file.present?` → `handle_soundtrack_upload(file, message)` (private)
- Otherwise → `handle_chat_message(message)` (private, extracted from original create)

### Form requirements
The chat form uses `html: { enctype: "multipart/form-data" }` in `form_with` so file uploads work with Turbo Streams.

### Stimulus targets
`chat-mode` controller targets: `tab`, `fileInput`, `attachLabel`, `filePreview`, `modeField`.
`data-controller="chat-input chat-mode"` are co-located on the same wrapper `div` — multiple controllers on a single element is fine in Stimulus.

### ARIA pattern
Tabs use `role="tablist"` / `role="tab"` / `aria-selected` for screen reader semantics. `aria-live="polite"` on the file preview `<p>` announces the selected filename.

### i18n keys added
Both `en.yml` and `it.yml` under `order_chat:` received:
- `mode_tabs_label`, `tab_music`, `attach_file_label`, `send_button_label`, `soundtrack_uploading_message`

Other locales (de, es, fr, pt) fall back to en — add translations there when those locales become active.

**How to apply:** When adding new mode-specific UI to the chat, follow this same pattern: hidden by default, Stimulus shows/hides, hidden `<input type="hidden">` carries the mode value to the controller.
