---
name: project-setup-decisions
description: Decisoes fechadas de setup da Secao 1 do Music AI Gen — gems, ENV, jobs, Sentry, Devise, Pundit, BaseService, brands.yml
metadata:
  type: project
---

Secao 1 concluida em 2026-05-25. Decisoes fechadas e nao reverter sem discussao:

**Why:** Estas decisoes foram explicitamente fechadas pelo usuario antes da implementacao para evitar retrabalho.

**How to apply:** Nunca propor alternativas a estas escolhas sem o usuario abrir a discussao.

- Background jobs: Solid Queue (nao Sidekiq). Filas nomeadas: default, critical, mailers, ai.
- Dev usa :async adapter — Solid Queue real so em production/staging.
- Testes: Minitest (nao RSpec).
- ENV vars: dotenv-rails em dev/test, Rails credentials apenas para MASTER_KEY.
- Admin (Administrate): adiado para Secao 16, nao adicionar agora.
- Anthropic SDK: gem `anthropic` sem pin de versao (1.43.0 instalado).
- TDD: pulado na Secao 1 (setup puro); volta na Secao 2+.

**Versoes instaladas (Gemfile.lock):**
- devise 4.9.4
- pundit 2.5.2
- aasm 5.5.2
- stripe 13.5.1
- anthropic 1.43.0
- sentry-rails 5.28.1 (sentry-ruby 5.28.1)
- webmock 3.26.2
- dotenv-rails 3.2.0

**Particularidade: brands.yml**
- config_for(:brands) retorna nil porque o YAML nao tem chaves por ambiente.
- Solucao: YAML.safe_load(File.read(path)).deep_symbolize_keys — contorna Bootsnap.
- Acesso: BRANDS_CONFIG[:b2b][:display_name] (simbolos em todos os niveis).

**Smoke tests confirmados:**
- Rails.env => "development"
- BRANDS_CONFIG[:b2b][:display_name] => "JinglePro"
- BaseService.ancestors inclui ActiveModel::Model e ActiveModel::Attributes
- bin/rails test: 0 runs, 0 failures, 0 errors
