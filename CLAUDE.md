# LARE — Instruções para o Claude

SaaS B2B de gestão imobiliária para agências. Centraliza o ciclo completo do aluguel: imóveis, contratos, cobrança, repasse ao proprietário, vistorias, documentos e relatórios financeiros.

---

## Stack

| Camada | Tecnologia |
|---|---|
| Linguagem | Ruby 4.0+ |
| Framework | Rails 8.1 |
| Banco de dados | PostgreSQL 16 |
| Frontend | Hotwire (Turbo + Stimulus), Tailwind CSS, ViewComponent |
| Background jobs | Solid Queue |
| Deploy | Kamal 2 (Docker, AWS Lightsail) |
| Monitoramento | Sentry |

---

## Comandos essenciais

```bash
bin/dev                          # inicia o servidor de desenvolvimento
bin/rails test                   # suite completa de testes
bin/rails test test/models/      # testes por categoria
bin/rails db:migrate             # roda migrations pendentes
kamal deploy                     # deploy de nova versão
```

---

## MCP Servers

Usado pelo agente `frontend-analyzer`. O servidor de desenvolvimento deve estar rodando (`bin/dev`) antes de acioná-lo.

```bash
# Instalar (primeira vez)
pnpm dlx playwright install chromium

# Registar os MCPs no Claude Code
claude mcp add playwright -- pnpm dlx @playwright/mcp@latest
claude mcp add filesystem -- pnpm dlx @modelcontextprotocol/server-filesystem $(pwd)
```

---

## Fluxo obrigatório de desenvolvimento (Agent Workflow)

**NUNCA escreva código de implementação sem seguir este fluxo:**

```
idea-validator → task-planner → tdd-architect → backend-architect if needed → frontend-architect if needed → minitest-runner → [security-engineer]
```

Para features de frontend, incluir análise visual antes do merge:

```
frontend-architect → frontend-analyzer → minitest-runner → [security-engineer]
```

### Etapas

**1. idea-validator** — SEMPRE o primeiro passo ao receber uma ideia nova, bug report vago ou proposta de refactor
- Lê README.md e db/schema.rb para entender o contexto atual
- Discute a ideia com o usuário: problema, valor, edge cases, alternativas mais simples
- Valida alinhamento com o modelo de negócio (SaaS B2B para agências imobiliárias)
- Só libera para o task-planner quando a ideia estiver bem definida
- **NÃO escreve código, NÃO produz planos técnicos**

**2. task-planner** — após validação da ideia, ANTES de qualquer implementação
- Lê README.md e db/schema.rb
- Analisa o código existente e padrões do projeto
- Produz um plano detalhado de implementação
- Aguarda aprovação antes de prosseguir
- **NÃO escreve código**

**3. tdd-architect** — OBRIGATÓRIO após aprovação do plano, ANTES de qualquer implementação
- Recebe o plano aprovado
- Define a estratégia de testes (unit, integration, system)
- Escreve os testes que devem FALHAR (fase red do TDD)
- Aciona minitest-runner para confirmar falha correta
- **NÃO escreve código de implementação**

**4. backend-architect** ou **frontend-architect** — implementação
- **backend-architect**: modelos, services, controllers, jobs, APIs, migrações
- **frontend-architect**: ViewComponents, Tailwind, Stimulus, acessibilidade
- Implementa seguindo o plano e fazendo os testes passarem (fase green)

**5. minitest-runner** — após implementação
- Roda os testes e confirma que todos passam
- Diagnostica falhas se houver
- Se a mudança tocar auth, pagamentos, upload de arquivos ou multi-tenant → aciona security-engineer

**6. security-engineer** — quando aplicável
- Revisão de segurança antes do merge
- Obrigatório para: autenticação, autorização, dados sensíveis, integrações externas

### Quando usar cada agent diretamente

| Situação | Agent |
|---|---|
| Ideia nova, bug vago ou proposta de refactor | `idea-validator` |
| Ideia validada, pronta para planejar | `task-planner` |
| Plano aprovado, antes de implementar | `tdd-architect` |
| Implementar backend (models, services, APIs) | `backend-architect` |
| Implementar frontend (UI, ViewComponent) | `frontend-architect` |
| Análise visual, acessibilidade, Turbo/Stimulus | `frontend-analyzer` |
| Rodar / debugar testes | `minitest-runner` |
| Revisão de segurança | `security-engineer` |
| Pesquisa técnica (APIs externas, regulações) | `research-scientist` |
| Documentação | `technical-writer` |
| Copies, anúncios, estratégia de aquisição de leads | `lare-growth-marketer` |

---

## Convenções do projeto

### Services (BaseService)
```ruby
class MyService < BaseService
  attribute :param, :string
  validates :param, presence: true

  def call
    return failure_result(errors) unless valid?
    # lógica
    success_result(value)
  end
end
```

### Enums
- **NUNCA** usar `none` como valor de enum — conflita com `ActiveRecord::Base.none`
- Usar `no_adjustment`, `not_applicable`, etc.

### Testes
- Framework: Minitest
- Services: testar `success_result` e `failure_result`
- FK de Transaction: `account_id: fa.id` (não `account: fa`)
