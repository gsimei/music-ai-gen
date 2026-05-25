---
name: brand-locale-secao5
description: BrandLocaleResolver service, I18n config, ApplicationController around_action e t_brand helper — decisoes e padroes da Secao 5
metadata:
  type: project
---

# Secao 5 — Brand/Locale Resolver (431 testes verdes)

## Decisoes fechadas

1. `around_action` (nao `before_action`) — thread safety com `I18n.with_locale { yield }`
2. Multi-host dev: `b2b.lvh.me` e `b2c.lvh.me` adicionados ao `brands.yml` com comentario dev-only
3. Cookie de locale: `httponly: true, expires: 1.year, secure: Rails.env.production?`
4. Host desconhecido: dev/test → fallback b2c silencioso; prod → failure_result(:unknown_host) → 404
5. `supported_locales` no YAML sao strings; convertidos para symbols via `.map(&:to_sym)` no service
6. `locale_param` (`?locale=xx`) so efetivo em `Rails.env.development?`
7. Lambda no `default:` do `t()` precisa de `->(*) {}` (nao `-> {}`) — Rails passa args opcionais

## Padrao de testabilidade para Rails.env

`BrandLocaleResolver#rails_env` e extraido como metodo privado para permitir override em testes.
Subclasses `DevResolver` e `ProdResolver` no test file fazem override sem monkey-patch.

```ruby
# No service:
def rails_env
  Rails.env
end

# No test file:
class DevResolver < BrandLocaleResolver
  def rails_env = ActiveSupport::EnvironmentInquirer.new("development")
end
```

**Why:** `Rails.stub(:env, ...)` nao funciona pois `Rails` e um Module; `objeto.stub` do Minitest requer que o objeto inclua Minitest::Mock. Subclasse e o padrao mais limpo e thread-safe.

## I18n config (application.rb)

```ruby
config.i18n.available_locales = %i[it en es fr de pt]
config.i18n.default_locale = :it
config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.yml").to_s]
```

NÃO configurado `i18n.fallbacks` — fallback fica no helper `t_brand`.

## Estrutura de locales criada

```
config/locales/
├── it.yml, en.yml, es.yml, fr.yml, de.yml, pt.yml   # bases com site_name + errors
└── brands/
    ├── b2b/  it.yml, en.yml, es.yml, fr.yml, de.yml
    └── b2c/  it.yml, en.yml, es.yml, fr.yml, de.yml, pt.yml
```

## ApplicationController

`@current_brand` setado via `attr_reader` e exposto via `helper_method :current_brand`.
`maybe_persist_locale_cookie` nao persiste em host .it (forcado) nem quando locale_param esta presente em dev.

## Teste de integracao (ActionDispatch::IntegrationTest)

Pattern: controller `TestProbeController < ApplicationController` definido dentro do test file.
`setup` redesenha routes; `teardown` chama `Rails.application.reload_routes!`.
Rota: `GET /test_probe` → `"brand=b2b locale=it"` (plain text).
