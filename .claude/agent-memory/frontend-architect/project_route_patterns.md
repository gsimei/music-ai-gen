---
name: project-route-patterns
description: Multi-brand routing conventions — how to add routes inside BrandConstraint blocks without named-helper collisions
metadata:
  type: project
---

Two `BrandConstraint` blocks (`:b2b`, `:b2c`) wrap all app routes. Named helpers are declared once in the b2b block and omitted in the b2c block to avoid `Invalid route name, already in use` errors.

For root routes specifically:
- B2B block: `root "controller#action", as: :root`
- B2C block: `get "/", to: "controller#action"` (plain GET — `root` always auto-assigns the name `root` even without `as:`, which collides)

**Why:** Rails registers the route helper name `root` automatically when `root` DSL is used, regardless of whether `as:` is provided. Using `get "/"` in the b2c block bypasses this.

**How to apply:** Any time a new route must exist in both brand blocks, declare it with `as: :name` in the b2b block and omit `as:` (or use `get` directly) in the b2c block.

See also: [[project_design_tokens]]
