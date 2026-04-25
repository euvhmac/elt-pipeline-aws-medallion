---
applyTo: '**'
---

# Copilot Instructions — elt-pipeline-aws-medallion

> Instruções foundational sempre carregadas. Define contexto, princípios e anti-patterns para todo desenvolvimento neste repositório.

---

## Contexto do Projeto

**Nome**: `elt-pipeline-aws-medallion`
**Tipo**: Plataforma analítica multi-tenant em AWS com arquitetura Medallion
**Status**: Recriação para portfólio público de uma plataforma corporativa interna (acesso original sob NDA)
**Autor**: Vhmac (`euvhmac` no GitHub, `euvhmendes@gmail.com`)

### Stack Principal

- **Storage**: Amazon S3 + Apache Iceberg
- **Engine SQL**: Amazon Athena (engine v3 / Trino)
- **Catálogo**: AWS Glue Data Catalog
- **Transformação**: dbt-core + dbt-athena-community
- **Orquestração**: Apache Airflow 2.9 (Docker Compose local)
- **Ingestão**: Gerador Python sintético (Faker + PyArrow)
- **IaC**: Terraform 1.7+
- **CI/CD**: GitHub Actions
- **Observabilidade**: SNS + Lambda + CloudWatch

### Arquitetura

Medallion 4-camadas: **Bronze → Silver → Gold → Platinum**
- Bronze: raw Parquet particionado (40 tabelas = 8 datamarts × 5 tenants)
- Silver: limpeza, padronização, unificação multi-tenant (30 modelos)
- Gold: star schema Kimball (8 dims + 6 facts + 2 DREs = 16 modelos)
- Platinum: visões de negócio por unidade (9 modelos)

**Tenants**: `unit_01`, `unit_02`, `unit_03`, `unit_04`, `unit_05` (apenas estes — nunca usar outros nomes).

---

## Idioma

- **Respostas e documentação**: Português brasileiro (PT-BR)
- **Código, identifiers, nomes técnicos**: Inglês
- **Commit messages**: PT-BR seguindo Conventional Commits
- **Comentários SQL/Python**: PT-BR quando explicam regra de negócio; inglês quando técnico

---

## Princípios Não-Negociáveis

### 1. Multi-Tenant First
Toda tabela, query, modelo, particionamento e teste **deve** considerar `tenant_id`.
- Tabelas Silver/Gold/Platinum têm coluna `tenant_id`
- Surrogate keys são compostas com `tenant_id`
- Queries têm `WHERE tenant_id = ...` quando aplicável (predicate pushdown)
- Particionamento Hive em S3 começa com `tenant_id=unit_NN/`

### 2. Cost-Conscious
Toda decisão técnica considera custo AWS. Free tier ($200 créditos) deve durar 12+ meses.
- Athena: partition pruning obrigatório, `bytes_scanned_cutoff_per_query` configurado
- S3: lifecycle policy (Bronze → IA após 30d)
- Iceberg: `OPTIMIZE` mensal + `VACUUM` retention 7d
- Lambda: timeout enxuto, memória mínima viável
- **PRs que adicionam recursos AWS justificam o custo**

### 3. Reproducibility
Clone limpo + `cp .env.example .env` + `make up` = ambiente funcionando.
- Sem hardcoded paths/IDs
- Sem dependência de estado oculto
- Versions pinned em `pyproject.toml`, `versions.tf`, `docker-compose.yml`
- Seeds determinísticos (seed fixa no gerador)

### 4. Security-First
- **Zero secrets hardcoded** — sempre Secrets Manager ou env var
- **`.env` é gitignored** (commit apenas `.env.example`)
- IAM least-privilege: nunca `Action: "*"` ou `Resource: "*"` sem condition
- S3 buckets: block public access + encryption SSE-S3 mínimo
- gitleaks pre-commit + CI obrigatório

### 5. Observable
- Logs estruturados JSON com campos: `timestamp`, `level`, `service`, `tenant_id`, `dag_id`, `task_id`
- **Nunca `print()`** em produção — usar `logging` ou `structlog`
- Failures críticos disparam SNS → Lambda → Slack em < 60s
- dbt artifacts (`manifest.json`, `run_results.json`) salvos em S3 toda execução

### 6. Idempotent
Re-run do mesmo workload produz o mesmo resultado.
- dbt incremental com `unique_key` correto
- Airflow tasks suportam retry sem duplicação
- Geração de dados com seed permite reprodução exata
- Terraform: `apply` repetido sem efeito quando estado convergiu

---

## Anti-Patterns Proibidos

Este repositório **rejeita** os seguintes padrões. Code review deve bloquear:

### SQL / dbt
- ❌ `SELECT *` em modelos Gold/Platinum (sempre listar colunas)
- ❌ Full table scans em Athena (sem `WHERE` de partition)
- ❌ `DOUBLE`/`FLOAT` para valores monetários (usar `DECIMAL(18,2)`)
- ❌ Modelos sem `unique_key` em incremental
- ❌ Modelos sem testes mínimos (PK not_null + unique)
- ❌ Subqueries aninhadas quando CTEs resolvem
- ❌ Lógica de negócio em Bronze (Bronze é raw)

### Python
- ❌ `print()` em código de produção (usar logging)
- ❌ `float` para dinheiro (usar `Decimal`)
- ❌ `except Exception` sem re-raise ou logging específico
- ❌ Globals mutáveis
- ❌ Funções públicas sem type hints
- ❌ Lógica de negócio dentro de DAG Airflow (extrair para `utils/`)

### Infrastructure / Terraform
- ❌ `terraform apply` direto em produção (usar PR + plan review)
- ❌ State local (sempre backend remoto S3 + DynamoDB lock)
- ❌ Hardcoded ARNs/IDs (usar `data` sources ou outputs)
- ❌ Recursos sem tags `Project`, `Environment`, `ManagedBy`
- ❌ IAM com `Action: "*"` ou `Resource: "*"` sem condition
- ❌ S3 bucket sem block public access
- ❌ Provider sem version pinning

### Git / Process
- ❌ `--no-verify` para bypassar pre-commit
- ❌ Force push em `main`
- ❌ Commits sem testes (quando código testável)
- ❌ Merge sem CI verde
- ❌ Secrets em commits (mesmo deletados depois — histórico fica)
- ❌ Commit messages em inglês (este repo usa PT-BR)

---

## Authoring

- **Todos os commits** devem ser autorados por `Vhmac <euvhmendes@gmail.com>`
- Usar `git -c user.name="Vhmac" -c user.email="euvhmendes@gmail.com" commit` quando necessário
- Co-author em PRs colaborativos com IA: incluir `Co-authored-by:` (oportunidade Pair Extraordinaire 👥)

---

## GitHub Achievements — Awareness

Ao executar tarefas, considerar oportunidades de farmar achievements:
- 🦈 **Pull Shark**: trabalhar via PR → develop → main em vez de commit direto
- 🤪 **YOLO**: merge sem review (em projetos solo, válido)
- 🔫 **Quickdraw**: fechar issue/PR em < 5 min
- 👥 **Pair Extraordinaire**: commits com co-author
- 🧠 **Galaxy Brain**: respostas aceitas em GitHub Discussions
- ⭐ **Starstruck**: stars (depende de terceiros)

Sempre alertar usuário quando uma ação criar oportunidade de achievement.

---

## Conventional Commits (PT-BR)

Formato: `<tipo>(<escopo>): <descrição em pt-br>`

**Tipos válidos**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`

**Escopos sugeridos**: `dbt`, `airflow`, `infra`, `generator`, `docs`, `ci`, `github`

**Exemplos**:
```
feat(dbt): adiciona modelo fct_devolucao com merge incremental
fix(airflow): corrige callback Slack quando task falha em retry
docs(adr): adiciona ADR-0006 sobre OpenLineage
chore(github): atualiza dependabot para incluir actions
```

Detalhes completos: [commits-prs.instructions.md](instructions/commits-prs.instructions.md).

---

## Referências Cruzadas

Instructions específicas escopadas via `applyTo`:
- [naming-conventions](instructions/naming-conventions.instructions.md) — single source of truth
- [dbt](instructions/dbt.instructions.md) — modelos, configs, testes
- [sql-athena](instructions/sql-athena.instructions.md) — dialeto Trino
- [data-modeling](instructions/data-modeling.instructions.md) — Kimball star schema
- [data-quality](instructions/data-quality.instructions.md) — pirâmide de testes
- [python](instructions/python.instructions.md) — padrões Python
- [airflow](instructions/airflow.instructions.md) — DAGs, callbacks, pools
- [terraform](instructions/terraform.instructions.md) — IaC, modules, tagging
- [security](instructions/security.instructions.md) — secrets, IAM, encryption
- [observability](instructions/observability.instructions.md) — logs, métricas, alerts
- [cost-awareness](instructions/cost-awareness.instructions.md) — anti-burn AWS
- [testing](instructions/testing.instructions.md) — pirâmide de testes
- [commits-prs](instructions/commits-prs.instructions.md) — processo

Documentação de produto em [docs/](../docs/) (PROJECT_BLUEPRINT, ARCHITECTURE_AWS, ADRs, etc.).

---

## Comportamento Esperado do Copilot

1. **Antes de codar**: ler instructions relevantes ao arquivo (via `applyTo` glob)
2. **Implementar > sugerir**: por padrão, criar/editar arquivos em vez de só descrever
3. **Validar contra anti-patterns**: bloquear sugestões que violam princípios
4. **Justificar trade-offs**: quando há decisão arquitetural, propor ADR
5. **Cost-aware**: ao adicionar recurso AWS, calcular custo aproximado
6. **Multi-tenant aware**: nunca esquecer `tenant_id` em modelos/queries novos
