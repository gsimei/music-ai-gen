---
name: project-overview
description: Visão geral do Music AI Gen — stack, marcas, mercados e arquitetura principal
metadata:
  type: project
---

Plataforma Rails 8.1 / Ruby 4.0 de geração de músicas personalizadas com AI. Multi-brand (B2B jingles + B2C presentes musicais), mercado europeu com foco na Itália.

**Why:** Produto SaaS com duas marcas independentes sob o mesmo backend monolito Rails.

**How to apply:** Sempre considerar o contexto multi-brand ao planejar qualquer feature — brand detectada por host, locale por host (.it força italiano) ou Accept-Language.

Stack confirmada:
- Rails 8.1.3, Ruby 4.0.5 (Bundler 4.0.12)
- PostgreSQL 16, Solid Queue (não Sidekiq), Solid Cache, Solid Cable
- Hotwire (Turbo + Stimulus), Tailwind CSS 4, Propshaft
- Auth: Devise + Pundit
- AI letras: Anthropic Claude (claude-opus-4-7)
- AI música: Mureka API (platform.mureka.ai)
- Storage: Cloudflare R2 (S3-compatible via ActiveStorage)
- Email: Postmark ou Resend (a decidir na seção de email)
- Deploy: Kamal 2

Nomes de domínio ainda são placeholders (jinglepro.it, musicaregalo.it) — estrutura configurável via config/brands.yml.
