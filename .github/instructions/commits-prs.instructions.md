---
applyTo: '**'
---

# Commits & Pull Requests

> Padrões de commits, branches e pull requests. Aplicável a todo desenvolvimento.

---

## Conventional Commits (PT-BR)

### Formato

```
<tipo>(<escopo>): <descrição em pt-br>

[corpo opcional explicando o porquê]

[footer: BREAKING CHANGE, Co-authored-by, Closes #N]
```

### Tipos válidos

| Tipo | Quando usar |
|---|---|
| `feat` | Nova feature/funcionalidade |
| `fix` | Correção de bug |
| `docs` | Mudanças em documentação |
| `refactor` | Refactor sem mudança de comportamento |
| `test` | Adicionar/ajustar testes |
| `chore` | Tarefas de build, deps, configuração geral |
| `perf` | Melhoria de performance |
| `ci` | Mudanças em CI/CD (workflows, hooks) |
| `build` | Mudanças em build system (poetry, docker) |

### Escopos sugeridos

| Escopo | Domínio |
|---|---|
| `dbt` | Modelos dbt, configs, macros |
| `airflow` | DAGs, callbacks, plugins |
| `infra` | Terraform |
| `generator` | Data generator Python |
| `docs` | Documentação |
| `ci` | GitHub Actions, pre-commit |
| `github` | `.github/` foundation |
| `seeds` | Seeds CSV |

### Regras

- **Descrição em PT-BR**, lowercase, sem ponto final
- **Imperativo**: "adiciona", "corrige", "remove" (não "adicionado", "adicionei")
- **Máximo 72 caracteres** na primeira linha
- **Corpo separado por linha em branco** (quando presente)
- **`BREAKING CHANGE:` no footer** se houver quebra de compatibilidade

### Exemplos válidos

```
feat(dbt): adiciona modelo fct_devolucao com merge incremental

fix(airflow): corrige callback Slack quando task falha em retry

docs(adr): adiciona ADR-0006 sobre OpenLineage

chore(github): adiciona copilot instructions e templates

refactor(generator): extrai SchemaValidator para módulo separado

test(dbt): adiciona testes de relationships em fct_vendas

perf(dbt): otimiza fct_vendas com partition pruning

ci(workflows): adiciona dbt-ci com state:modified+ defer

build(docker): atualiza imagem airflow para 2.9.1

feat(airflow)!: migra para TaskFlow API

BREAKING CHANGE: DAGs antigas precisam refactor para @task decorator
```

### Exemplos inválidos

❌ `Update files` (sem tipo, sem escopo, vago)
❌ `feat: added new model` (inglês, voz passiva)
❌ `fix(dbt): Fixes the bug.` (capitalizado, com ponto)
❌ `chore: stuff` (descrição inútil)

---

## Branches — Gitflow Obrigatório

### Modelo de branching

```
main      ●────────────●────────────●────────●  (releases, tags CalVer)
           ╲          ╱ ╲          ╱╲       ╱
            ╲        ╱   ╲        ╱  ╲hotfix
develop  ────●──●──●─────●──●──●─────●──●──●  (integração contínua)
              ╲ ╲ ╲      ╲ ╲ ╲       ╲ ╲ ╲
               feature branches (efêmeras)
```

| Branch | Propósito | Origem | Destino |
|---|---|---|---|
| `main` | Código em produção / release | — | (recebe de `develop` ou `hotfix/*`) |
| `develop` | Integração contínua de features | `main` (uma vez) | `main` (via PR de release) |
| `feat/*` | Desenvolvimento de feature/sprint | `develop` | `develop` (via PR) |
| `fix/*` | Correção de bug não-urgente | `develop` | `develop` (via PR) |
| `hotfix/*` | Correção urgente em produção | `main` | `main` E `develop` (cherry-pick) |
| `docs/*` | Documentação | `develop` | `develop` |
| `chore/*` | Tarefas de manutenção | `develop` | `develop` |

### Regras inegociáveis (Sprint 1+)

1. ❌ **Nunca commit direto em `main`**
2. ❌ **Nunca commit direto em `develop`** (exceto typos triviais em README)
3. ❌ **Nunca force push em `main` ou `develop`**
4. ✅ **Toda mudança via feature branch + PR**
5. ✅ **PR exige CI verde** + checklist completo
6. ✅ **Branches deletadas após merge**
7. ✅ **Squash merge** (default) para histórico linear

### Fluxo padrão — Feature/Sprint

```bash
# 1. Atualizar develop
git checkout develop
git pull origin develop

# 2. Criar feature branch
git checkout -b feat/sprint-1-fundacao-local

# 3. Trabalhar (commits frequentes, Conventional Commits PT-BR)
git add .
git -c user.name="Vhmac" -c user.email="euvhmendes@gmail.com" commit -m "feat(airflow): adiciona docker-compose com postgres e redis"

# 4. Push e abrir PR
git push -u origin feat/sprint-1-fundacao-local
gh pr create --base develop \
  --title "feat(airflow): fundação local Docker Compose" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md

# 5. Após aprovação: squash merge via UI ou CLI
gh pr merge --squash --delete-branch

# 6. Sync local
git checkout develop
git pull origin develop
git branch -d feat/sprint-1-fundacao-local
```

### Fluxo de Release — `develop → main`

Ao final de cada sprint:

```bash
# 1. Garantir develop atualizado e CI verde
git checkout develop && git pull

# 2. Abrir PR de release
gh pr create --base main --head develop \
  --title "release(2025.05.0): Sprint 1 — Fundação Local" \
  --body "Conteúdo da Sprint: ..."

# 3. Após merge: criar tag CalVer
git checkout main && git pull
git tag -a 2025.05.0 -m "Sprint 1: Fundação Local Docker Compose"
git push origin 2025.05.0

# 4. GitHub Release
gh release create 2025.05.0 \
  --title "Sprint 1 — Fundação Local" \
  --notes-file docs/releases/2025.05.0.md
```

### Fluxo de Hotfix — Bug em produção

```bash
# 1. Sair de main (não de develop)
git checkout main && git pull
git checkout -b hotfix/athena-cutoff-100gb

# 2. Corrigir + commit
git commit -m "fix(infra): aumenta athena cutoff para 100GB temporariamente"

# 3. PR para main
gh pr create --base main --title "hotfix(infra): athena cutoff"

# 4. Após merge em main: portar para develop
git checkout develop && git pull
git cherry-pick <sha-do-hotfix>
git push origin develop
```

### Branches protegidas (configurar no GitHub Settings)

**`main`**:
- Require PR before merging
- Require status checks (CI)
- Require linear history (squash merge)
- Restrict who can push (admins only)
- No force push, no deletion

**`develop`**:
- Require PR before merging
- Require status checks (CI)
- No force push, no deletion

### Naming detalhado

| Tipo | Padrão | Exemplo |
|---|---|---|
| Feature/Sprint | `feat/<scope>-<short-desc>` | `feat/sprint-1-fundacao-local` |
| Feature menor | `feat/<scope>-<desc>` | `feat/dbt-fct-devolucao` |
| Fix | `fix/<scope>-<bug>` | `fix/airflow-callback-retry` |
| Hotfix | `hotfix/<scope>-<bug>` | `hotfix/athena-cutoff-100gb` |
| Docs | `docs/<scope>` | `docs/adr-openlineage` |
| Refactor | `refactor/<scope>` | `refactor/airflow-utils-extract` |
| Chore | `chore/<scope>` | `chore/deps-update` |

### Lifecycle visual

```
develop ●─────────────────────●───  ← PR merged
         ╲                   ╱
          ╲ feat/sprint-1   ╱
           ●──●──●──●──●──●        ← work happens here
           │                ╲
           │                 ╲ deleted after merge
           └─ created from develop
```

### Regras gerais
- **Branches efêmeras**: deletar após merge (`gh pr merge --delete-branch`)
- **Sync regular**: `git rebase develop` em features de longa duração
- **Sem force push** em `main`/`develop`
- **`--force-with-lease` permitido** em feature branches próprias

### Exceções aceitas

- Setup pré-Sprint 1 (commits diretos em `main` no Sprint 0): aceito, este foi o caso histórico
- Typo em README: commit direto em `develop` aceito
- `main` recebe direto **apenas** de `develop` ou `hotfix/*`

---

## Pull Requests

### Title
- Igual à primeira linha do commit principal (Conventional Commits PT-BR)
- Exemplo: `feat(dbt): adiciona modelo fct_devolucao com merge incremental`

### Body
Usar template `.github/PULL_REQUEST_TEMPLATE.md`. Sempre preencher:
- **Descrição**: o que muda e por quê
- **Componentes afetados**: checkboxes
- **Como foi testado**: comandos, screenshots
- **Checklist**: completo antes de mergear
- **Issues**: `Closes #N`

### Tamanho
- **PR pequeno**: < 400 linhas alteradas (ideal)
- **PR médio**: 400-800 linhas
- **PR grande**: > 800 linhas — preferir quebrar em múltiplos PRs

### Review

- **Self-merge permitido em projeto solo** (oportunidade YOLO 🤪)
- **Em projetos colaborativos**: 1 approval mínimo + CI verde
- **Comentários de review**: respondidos antes do merge
- **Suggestions**: aceitas via UI quando aplicável

### Merge strategy

**Squash merge** (default):
- Histórico linear em `main`
- Mensagem do squash = title do PR (Conventional Commits)
- Branch deletada automaticamente

**Rebase** apenas para sync com `main`:
```bash
git checkout feat/minha-branch
git rebase main
git push --force-with-lease
```

---

## Co-authoring (Pair Extraordinaire 👥)

Quando trabalhar pareado com outro humano OU com IA assistente:

```
feat(dbt): adiciona modelo fct_devolucao

Implementa lógica de devoluções por unidade com merge incremental.
Inclui testes de relationships com fct_vendas.

Co-authored-by: GitHub Copilot <noreply@github.com>
```

Achievement opportunity: Pair Extraordinaire 👥 ao incluir co-authors em PRs.

---

## Pre-Merge Checklist (verificar via CI + manual)

- [ ] Conventional Commits em PT-BR
- [ ] Pre-commit hooks passaram (sqlfluff, ruff, terraform fmt, gitleaks)
- [ ] Testes passaram (`make dbt-test`, `pytest`)
- [ ] CI verde (secrets-scan + dbt-ci/terraform-ci se aplicável)
- [ ] Documentação atualizada (se aplicável)
- [ ] ADR criado (se decisão arquitetural)
- [ ] Custo AWS considerado (se infra) — comentário no PR
- [ ] Multi-tenant respeitado (`tenant_id` em queries/tabelas novas)
- [ ] Sem secrets hardcoded
- [ ] Sem breaking change não-documentado
- [ ] Branch atualizada com `main`

---

## Commits via Git CLI

### Identidade
Sempre garantir que commits são autorados como Vhmac:

```bash
# Por commit (mais seguro):
git -c user.name="Vhmac" -c user.email="euvhmendes@gmail.com" commit -m "..."

# Ou globalmente (uma vez):
git config --global user.name "Vhmac"
git config --global user.email "euvhmendes@gmail.com"
```

### Co-author footer
```bash
git commit -m "feat(dbt): adiciona modelo X

Co-authored-by: GitHub Copilot <noreply@github.com>"
```

### Amend / fixup
```bash
# Amend último commit (antes de push)
git commit --amend

# Fixup commit anterior (squash automático no rebase)
git commit --fixup=<sha>
git rebase -i --autosquash main
```

---

## Tags / Releases

**CalVer**: `YYYY.MM.PATCH`

```bash
git tag -a 2025.05.0 -m "Sprint 1: fundação local Docker Compose"
git push origin 2025.05.0
```

GitHub Releases gerados via `gh release create`:
```bash
gh release create 2025.05.0 \
  --title "Sprint 1 — Fundação Local" \
  --notes-file docs/releases/2025.05.0.md
```

---

## Anti-Patterns Proibidos

- ❌ Commit messages em inglês (este repo usa PT-BR)
- ❌ `git commit --no-verify` (bypass de hooks)
- ❌ **Commit direto em `main`** (Sprint 1+)
- ❌ **Commit direto em `develop`** (exceto typos triviais)
- ❌ **Pular gitflow** (não criar feature branch)
- ❌ Force push em `main` ou `develop`
- ❌ Commits gigantes ("WIP everything")
- ❌ Mensagens vagas (`fix stuff`, `update`, `wip`)
- ❌ Múltiplos commits "fix typo" em vez de squash
- ❌ Merge direto sem CI
- ❌ Tags fora do CalVer (`v1.0.0`, `release-1`)
- ❌ Branch sem prefixo de tipo (`minha-feature` em vez de `feat/minha-feature`)
- ❌ PR de feature direto para `main` (deve ser para `develop`)
- ❌ Hotfix indo só para `main` sem cherry-pick para `develop`

---

## GitHub Achievements — Oportunidades

Ao executar workflows de PR/commits, alertar sobre:

| Achievement | Como farmar |
|---|---|
| 🦈 Pull Shark | Mergear PR (mesmo solo) |
| 🤪 YOLO | Mergear PR sem review |
| 🔫 Quickdraw | Fechar issue/PR em < 5 min |
| 👥 Pair Extraordinaire | Commit com co-author |
| 🧠 Galaxy Brain | Resposta aceita em Discussion |
| ⭐ Starstruck | Stars no repo (depende de terceiros) |

Sempre alertar quando uma ação habilitar achievement.
