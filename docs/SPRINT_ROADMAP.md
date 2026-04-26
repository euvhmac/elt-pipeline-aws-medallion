# Sprint Roadmap

Plano de execução em 8 sprints, com critérios de aceite QA + Tech Lead por sprint. Cada sprint produz artefatos verificáveis e tem **definition of done** explícito.

---

## Visão Geral

| Sprint | Foco | Duração estimada |
|---|---|---|
| **Sprint 0** | Preparação & Documentação Inicial | 1 dia |
| **Sprint 1** | Fundação Local (Dev Environment) | 2-3 dias |
| **Sprint 2** | Infraestrutura AWS (Terraform) | 2 dias |
| **Sprint 2.5** | Refino do Gerador (Histórico + Sazonalidade) | 0.5 dia |
| **Sprint 3** | Camada de Ingestão (Bronze) | 2 dias |
| **Sprint 4** | Camada de Transformação (dbt-athena) | 4-5 dias |
| **Sprint 5** | Orquestração (Airflow Local) | 2 dias |
| **Sprint 6** | Observabilidade & Notificações | 2 dias |
| **Sprint 7** | CI/CD & Quality Gates | 1-2 dias |
| **Sprint 8** | Polimento de Portfólio | 2 dias |

---

## Sprint 0 — Preparação & Documentação Inicial

### Objetivo
Estabelecer base de documentação completa antes de escrever qualquer código novo. Garantir que o repo está sanitizado e renomeado.

### Tasks

- [x] **S0.1** — Auditoria final de sanitização (gitleaks + grep zero-tolerance)
- [x] **S0.2** — Renomear repo: `elt-pipeline-databricks` → `elt-pipeline-aws-medallion`
- [x] **S0.3** — Criar bateria completa de docs (este documento + 13 outros + 5 ADRs)
- [x] **S0.4** — Reescrever `README.md` root com narrativa de portfólio
- [x] **S0.5** — Adicionar CONTRIBUTING.md, LICENSE (MIT), CODE_OF_CONDUCT.md
- [x] **S0.6** — Configurar GitHub repo: descrição, topics, homepage

### Critério QA
- `gitleaks detect --source . --redact` → zero high severity
- Grep manual em todo histórico: zero referências a empresas/ERPs originais
- Todos os links internos da documentação resolvem
- README renderiza corretamente no GitHub

### Critério Tech Lead
- Documentação cobre: visão, arquitetura, decisões (ADRs), execução, custos, narrativa de entrevista
- Estrutura permite que outsider entenda projeto em < 5 minutos
- Plano de sprints é defensável com critérios de aceite claros

### Definition of Done
- [ ] Push da Sprint 0 para `main` no GitHub
- [ ] GitHub repo com descrição + topics atualizados
- [ ] Issues abertas para Sprints 1-8 (kanban em GitHub Projects)

---

## Sprint 1 — Fundação Local (Dev Environment)

### Objetivo
Stack completa rodando localmente com `make up`, sem dependência de cloud ainda.

### Tasks

- [x] **S1.1** — Estrutura monorepo:
  ```
  ├── dbt/                  (skeleton: dbt_project.yml + profiles_example.yml)
  ├── airflow/              (docker-compose.yml + dags/ + plugins/)
  ├── data-generator/       (src + tests + README)
  ├── infra/                (skeleton: README com plano)
  └── docs/                 (já existia)
  ```
- [x] **S1.2** — `airflow/docker-compose.yml`:
  - Airflow 2.9.3-python3.11 (LocalExecutor)
  - Postgres 15 metadata
  - Volume mounts: `./dags`, `../dbt`, `../data-generator`
  - Provider AWS pré-instalado via `_PIP_ADDITIONAL_REQUIREMENTS`
- [x] **S1.3** — `data-generator/`:
  - 23 schemas PyArrow (8 datamarts) — Decimal para dinheiro
  - Geradores Faker (locale pt_BR) com FKs referenciais
  - Logger JSON estruturado
  - CLI Click: `generate` + `validate`
  - 8 testes pytest passando
- [x] **S1.4** — `dbt/profiles_example.yml` para Athena (env vars, sem hardcode)
- [x] **S1.5** — `Makefile` com targets: `up`, `down`, `nuke`, `seed`, `seed-validate`, `dbt-*`, `lint`, `test`, `compose-config`
- [x] **S1.6** — `pyproject.toml` com deps `pyarrow`, `faker`, `click`, `boto3`, `ruff`, `pytest`

### Critério QA — RESULTADO
- ✅ `docker compose -f airflow/docker-compose.yml --env-file .env.example config -q` → exit 0
- ✅ `pytest data-generator/tests` → 8/8 passing
- ✅ `ruff check data-generator/` → All checks passed
- ✅ Smoke CLI: `--volume-multiplier 0.05` × 2 tenants → 46 parquets gerados e validados
- ✅ Schemas validam com `pyarrow.parquet.read_schema()` (teste `test_write_local_cria_arquivo_e_le_de_volta`)

### Critério Tech Lead — RESULTADO
- ✅ Volume mounts permitem editar dbt sem rebuild de imagem
- ✅ Logs estruturados JSON (timestamp/level/service/tenant_id/datamart/table/rows)
- ✅ `.env.example` documenta todas variáveis necessárias
- ✅ Ausência de hardcoded paths (uso de `pathlib.Path`)
- ✅ Workflows CI: `compose-validate.yml` + `data-generator-tests.yml`

### Definition of Done — STATUS
- [x] README.md root com seção "Quickstart" funcional
- [x] CI verifica `docker compose config` (workflow `compose-validate.yml`)
- [x] Push da Sprint 1 com Conventional Commits PT-BR
- [x] PR `feat/sprint-1-fundacao-local → develop`

---

## Sprint 2 — Infraestrutura AWS (Terraform)

### Objetivo
Provisionar infra AWS via Terraform, com módulos reutilizáveis e backend remoto.

### Tasks

- [x] **S2.1** — Bootstrap backend (manual única vez):
  - S3 bucket para state: `elt-pipeline-tfstate-${aws_account_id}`
  - DynamoDB table para lock: `elt-pipeline-tfstate-lock`
- [x] **S2.2** — Módulo `infra/modules/s3-medallion/`:
  - 4 buckets (bronze/silver/gold/platinum) + 1 athena-results
  - Versioning, encryption, lifecycle (mover Bronze para IA após 30d)
- [x] **S2.3** — Módulo `infra/modules/glue-catalog/`:
  - 5 databases (audit, bronze, silver, gold, platinum)
  - Permissões básicas
- [x] **S2.4** — Módulo `infra/modules/iam-roles/`:
  - User para dbt-athena (least-privilege: S3 read/write + Glue + Athena)
  - Role para Lambda slack-notifier
- [x] **S2.5** — Módulo `infra/modules/secrets-manager/`:
  - Secret `slack-webhook-url` (placeholder)
- [x] **S2.6** — `infra/envs/dev/`:
  - `main.tf` chamando módulos
  - `variables.tf` + `terraform.tfvars` (gitignored)
  - `versions.tf` com provider AWS pinning + backend S3 remoto
- [x] **S2.7** — Módulo extra `infra/modules/athena-workgroup/` (cutoff 10GB)

### Critério QA — RESULTADO
- ✅ `terraform fmt -recursive` aplicado
- ✅ `terraform validate` em todos os módulos
- ✅ `terraform plan` em dev → 31 recursos a criar (revisado)
- ✅ `terraform apply` → 31 recursos criados sem erro

### Critério Tech Lead — RESULTADO
- ✅ Módulos parametrizados (zero hardcoded)
- ✅ Backend remoto S3 + DynamoDB lock funcionando
- ✅ `terraform apply` em < 2 min em dev
- ✅ Custo estimado < $0.50/mês com infra ociosa
- ✅ IAM least-privilege (sem `Action:*` ou `Resource:*` sem condition)
- ✅ S3 com block public access + SSE-S3 + tags Project/Environment/ManagedBy/Owner

### Definition of Done — STATUS
- [x] `terraform apply` no env dev executou sem erros (31 recursos)
- [x] `aws s3 ls` lista 6 buckets (5 medallion + 1 athena-results)
- [x] `aws glue get-databases` retorna 5 databases
- [x] `aws athena list-work-groups` confirma `elt-pipeline-dev`
- [x] PR `feat/sprint-2-infra-terraform → develop` mergeado (#4)

---

## Sprint 2.5 — Refino do Gerador (Histórico + Sazonalidade)

### Motivação
Sprint 1 entregou um gerador funcional para 1 dia, mas com volumes baixos e sem realismo temporal. Antes de subir Bronze para o S3 (Sprint 3), refatoramos o gerador para produzir **dataset historico multi-anos** com características essenciais para BI: sazonalidade, crescimento, pesos por tenant e dimensões estáveis no tempo.

### Tasks

- [x] **S2.5.1** — `config.py`: bumps de volume e novos parâmetros
  - Volumes de FACTS recalibrados (vendas 800/dia, lancamentos 1.500/dia, etc.)
  - `TENANT_WEIGHTS` (unit_01=1.5 → unit_05=0.4)
  - `SEASONALITY_MONTH` (jan=0.85, fev=0.75, nov=1.35, dez=1.55)
  - `ANNUAL_GROWTH_RATE = 0.15` (15%/ano linear desde `HISTORY_START_DEFAULT`)
  - `DIM_GROWING_DAILY_INCREMENT_PCT = 0.002` (0.2%/dia novos cadastros)
  - Sets `DIM_STATIC` (7 tabelas) e `DIM_GROWING` (6 tabelas)
- [x] **S2.5.2** — `orchestrator.py`: nova função `generate_range(start, end, ...)`
  - Streaming via yield (não acumula tudo em memória)
  - DIM_STATIC geradas apenas no primeiro dia; pool de IDs reusado
  - DIM_GROWING: volume cheio dia 1, incremento diário nos demais (FKs cumulativas)
  - FACTS: gerados todo dia, modulados por `tenant_weight × seasonality × growth × multiplier`
  - `refs` por tenant (universos de IDs isolados)
- [x] **S2.5.3** — `cli.py`: flags `--start-date` e `--end-date`
  - Quando ambas presentes → modo range histórico
  - Sem elas → modo single-day legado preservado
  - Logging estruturado com `mode` (`single_day` | `range`)

### Critério QA — RESULTADO
- ✅ `pytest data-generator/tests` → 8/8 passing (regressão zero)
- ✅ `ruff check data-generator/src` → All checks passed
- ✅ Smoke 14 dias × 2 tenants (mult=0.05): ratio unit_01/unit_05 ~3.75 (esperado 1.5/0.4 ≈ 3.75)
- ✅ Sazonalidade validada: vendas jan=66/dia → fev=58/dia (queda ~12%, esperado 0.85→0.75)
- ✅ Dimensões estáveis: `vendedores` não regenera entre dias (pool reusado)
- ✅ Crescimento de DIMs: `clientes` cresce ~0.2%/dia × dias do range

### Critério Tech Lead — RESULTADO
- ✅ Backward compatibility: `generate_all()` antiga preservada (single-day)
- ✅ Streaming generator: pipeline pode escrever cada `(tenant, dia)` direto sem OOM
- ✅ Volume realista para BI: ~2M vendas / ~4M itens / ~3M lançamentos em 28 meses × 5 tenants
- ✅ Tamanho final estimado em S3 Bronze (Parquet snappy): ~1-2 GB total (custo ínfimo)
- ✅ Sem dados reais; sem degradação de performance vs Sprint 1

### Definition of Done
- [x] PR `feat/sprint-2.5-generator-historico → develop` mergeado
- [x] CLI documentada para uso histórico: `python -m data_generator generate --start-date 2024-01-01 --end-date 2026-04-26`
- [x] Smoke documentado neste roadmap

---

## Sprint 3 — Camada de Ingestão (Bronze)

### Objetivo
Pipeline de ingestão funcional: gerador local → S3 Bronze → tabelas Athena navegáveis.

### Tasks — RESULTADO

- [x] **S3.1** — `writers.py`: nova `write_s3()` (boto3 `put_object` + SSE-S3 + Hive partition key)
- [x] **S3.2** — `cli.py`: `--output s3://...` aceito; modo single-day e range cobrem S3
- [x] **S3.3** — `export_glue_schemas.py`: gera `glue_tables.auto.tfvars.json` a partir do `SCHEMA_REGISTRY` (single source of truth)
- [x] **S3.4** — Módulo Terraform `glue-tables` com **Athena Partition Projection** (zero `batch_create_partition` / zero `MSCK REPAIR`)
  - 23 tabelas Bronze criadas em `bronze_dev`
  - Projection: `tenant_id` (enum `unit_01..05`), `year` (2024-2027), `month` (1-12), `day` (1-31)
  - `storage.location.template` com `s3://elt-pipeline-bronze-dev/<datamart>/<table>/tenant_id=...`
- [x] **S3.5** — DAG `airflow/dags/dag_synthetic_source.py`:
  - Task `generate_and_upload` (BashOperator → CLI com `--output s3://...`)
  - Task `validate_athena` (PythonOperator → `SELECT COUNT(*)` + poll execução)
- [x] **S3.6** — Smoke E2E real: gerar `unit_01/corporativo/2025-04-25` → S3 → Athena
  - Geração: 80 funcionários
  - Athena `SELECT COUNT(*)` retorna **80** (match exato)

### Critério QA — RESULTADO
- ✅ Tabelas Bronze acessíveis via Athena (23 criadas em `bronze_dev`)
- ✅ Counts entre Pandas (geração) e Athena query são idênticos (80 = 80)
- ✅ Particionamento via projection: zero scan de catálogo, zero `MSCK REPAIR`
- ✅ Custo: tabelas Glue grátis, queries Athena por bytes scanned (cutoff 10GB no workgroup)

### Critério Tech Lead — RESULTADO
- ✅ Decisão arquitetural documentada: Partition Projection > batch_create_partition (zero coordenação pipeline ↔ catálogo)
- ✅ Schemas single-source-of-truth: `schemas.py` Python → JSON tfvars → Terraform Glue (sem duplicação)
- ✅ Idempotência: re-upload do mesmo dia sobrescreve `part-0000.snappy.parquet`; projection ignora partições vazias
- ✅ Logs estruturados JSON com `tenant_id`, `datamart`, `table`, `s3_uri`, `rows`, `size_bytes`
- ✅ SSE-S3 (`AES256`) em todo upload via boto3
- ✅ Testes: 11/11 pytest passing, ruff clean

### Definition of Done
- [x] DAG `dag_synthetic_source` carrega no Airflow (parse OK, ruff clean)
- [x] `terraform apply` cria 23 tabelas Glue Bronze
- [x] Smoke E2E real (S3 + Athena) confirma round-trip
- [ ] Backfill histórico 2024-01-01 → 2026-04-26 (deferido; rodaremos em Sprint 5 com Airflow real)
- [ ] dbt source freshness em `dbt/sources.yml` (deferido para Sprint 4)

---

## Sprint 4 — Camada de Transformação (dbt-athena)

### Objetivo
Migrar 55 modelos dbt do dialeto Databricks SQL para Trino/Athena, mantendo lógica de negócio.

### Tasks

- [ ] **S4.1** — Configurar `dbt-athena-community` em `pyproject.toml`
- [ ] **S4.2** — Adaptar `dbt_project.yml`:
  - `+table_type: iceberg`
  - `+incremental_strategy: merge`
  - `+on_schema_change: append_new_columns`
- [ ] **S4.3** — Migrar **30 modelos Silver** (1-2 dias):
  - `silver_dw_*` em `dbt/models/silver/`
  - Substituir funções Spark→Trino (ver [MIGRATION_FROM_AZURE.md](MIGRATION_FROM_AZURE.md))
  - Validar `dbt run --select silver` em batches
- [ ] **S4.4** — Migrar **16 modelos Gold** (1 dia):
  - Dimensions: `dim_calendrio`, `dim_clientes`, `dim_produtos`, ...
  - Facts: `fct_vendas`, `fct_faturamento`, `fct_devolucao`, ...
  - DRE: `dre_contabil`, `dre_gerencial`
- [ ] **S4.5** — Migrar **9 modelos Platinum** (1 dia):
  - DRE por unidade (5 modelos)
  - Controle de inadimplentes
  - Estruturas DRE auxiliares
- [ ] **S4.6** — Migrar testes:
  - Schema tests (not_null, unique, accepted_values, relationships)
  - Singular tests (custom SQL em `dbt/tests/`)
  - dbt-expectations para validações avançadas
- [ ] **S4.7** — `dbt docs generate` + upload S3 + GitHub Pages

### Critério QA
- `dbt build` executa em < 15 min, zero falhas
- Cobertura de testes ≥ 80% (cada fact tem PK test + relationships)
- `dbt source freshness` passa
- `dbt docs serve` renderiza lineage completo

### Critério Tech Lead
- Modelos Silver são idempotentes (re-run produz mesmo resultado)
- Estratégia incremental usa `unique_key` correto + lookback window
- Surrogate keys via `dbt_utils.generate_surrogate_key`
- Modelos Platinum são views (zero custo armazenamento)
- Refatoração documentada quando SQL Spark precisou mudar significativamente

### Definition of Done
- [ ] 55 modelos rodam com sucesso
- [ ] `dbt test` retorna 0 falhas
- [ ] Manifest e run_results uploadados para `s3://...-dbt-artifacts/`
- [ ] `dbt docs` publicado em GitHub Pages

---

## Sprint 5 — Orquestração (Airflow Local)

### Objetivo
DAGs Airflow orquestrando o pipeline completo com Datasets event-driven.

### Tasks

- [ ] **S5.1** — DAG `dag_synthetic_source` (refinada da Sprint 3)
- [ ] **S5.2** — DAG `dag_dbt_aws_detailed`:
  - `schedule=[8 datasets bronze]`
  - TaskGroups: silver_layer, gold_layer, platinum_layer, tests_layer
  - 1 BashOperator por modelo (granularidade)
  - max_active_tasks=8 (limite paralelismo Athena)
- [ ] **S5.3** — `airflow/dags/utils/callbacks.py`:
  - `task_failure_alert` (publish SNS)
  - `dag_failure_alert`
- [ ] **S5.4** — Variables / Connections via `airflow_settings.yaml` (astro CLI compat)
- [ ] **S5.5** — Volumes Docker: `dbt/`, `dags/`, `data-generator/` montados read-only

### Critério QA
- Trigger manual `dag_synthetic_source` → `dag_dbt_aws_detailed` dispara automaticamente em < 30s
- Pipeline completo (source → bronze → silver → gold → platinum → tests) executa em < 30 min
- Logs claros e rastreáveis: cada task tem `dag_id.task_id` no log

### Critério Tech Lead
- DAG estrutura segue padrão dos repos baseline (referência interna)
- Retries configurados: 2 retries, 5min delay
- Timeouts apropriados: 20 min por task
- Task naming: `build_<layer>_<model>` para visibilidade no UI

### Definition of Done
- [ ] Ambas DAGs aparecem no Airflow UI
- [ ] Backfill manual funciona
- [ ] Logs de execução exportados para teste de observabilidade

---

## Sprint 6 — Observabilidade & Notificações

### Objetivo
Detectar falhas e ter visibilidade de saúde do pipeline.

### Tasks

- [ ] **S6.1** — Terraform: SNS topic `pipeline-alerts`
- [ ] **S6.2** — Terraform + código: Lambda `slack-notifier`:
  - Recebe SNS message
  - Formata Slack Block Kit
  - POST webhook (URL via Secrets Manager)
- [ ] **S6.3** — CloudWatch Dashboard:
  - Athena queries: tempo médio, scan, falhas
  - S3: tamanho por bucket, custo estimado
  - Métricas custom: contagem de tasks/dia
- [ ] **S6.4** — dbt artifacts → S3:
  - `manifest.json`, `run_results.json` versionados
  - Parsing futuro para lineage / Datafold-like
- [ ] **S6.5** — Logs Airflow → CloudWatch (opcional):
  - Bash com `aws logs put-log-events` no callback

### Critério QA
- Forçar falha (e.g., dbt model com erro) → Slack recebe alerta < 60s
- CloudWatch Dashboard mostra última execução
- dbt artifacts queriáveis via Athena (`SELECT * FROM dbt_runs`)

### Critério Tech Lead
- Alerta inclui: DAG ID, task ID, traceback, link para Airflow UI
- Lambda tem timeout 30s + dead letter queue
- Custo total observabilidade < $1/mês

### Definition of Done
- [ ] Falha proposital → mensagem em #data-alerts
- [ ] Dashboard com nome `elt-pipeline-aws-medallion-${env}`
- [ ] Documentação `docs/RUNBOOK.md` atualizada com procedimento de troubleshooting

---

## Sprint 7 — CI/CD & Quality Gates

### Objetivo
Bloquear merges com problemas; automatizar validações.

### Tasks

- [ ] **S7.1** — `.github/workflows/secrets-scan.yml`:
  - gitleaks em todo PR
- [ ] **S7.2** — `.github/workflows/dbt-ci.yml`:
  - Trigger: PR alterando `dbt/**`
  - Steps: `dbt deps` → `dbt parse` → `dbt compile` → `dbt build --select state:modified+`
  - Defer: produção state (artifacts S3)
- [ ] **S7.3** — `.github/workflows/terraform-ci.yml`:
  - Trigger: PR alterando `infra/**`
  - Steps: `fmt -check` → `validate` → `plan` → `tfsec` → `checkov`
  - Comenta `plan` no PR
- [ ] **S7.4** — `.sqlfluff` config:
  - Dialect: athena/trino
  - Rules: aliasing, capitalization, layout
- [ ] **S7.5** — `.pre-commit-config.yaml`:
  - sqlfluff
  - dbt-checkpoint
  - terraform fmt
  - gitleaks
- [ ] **S7.6** — Branch protection rules em `main`:
  - PRs obrigatórios
  - Status checks: secrets-scan + dbt-ci + terraform-ci
  - Não permitir force-push

### Critério QA
- PR com SQL inválido → CI vermelho, merge bloqueado
- PR com secret hardcoded → bloqueado por gitleaks
- PR válido → todos checks verdes em < 5 min

### Critério Tech Lead
- Workflows usam cache (pip, dbt packages) para acelerar
- `dbt build --select state:modified+` evita rodar suite completa
- terraform plan respeita workspace (dev por padrão)

### Definition of Done
- [ ] Demo de PR bloqueado por cada quality gate
- [ ] README badges de CI status verdes
- [ ] `CONTRIBUTING.md` documenta o processo de PR

---

## Sprint 8 — Polimento de Portfólio

### Objetivo
Tornar o projeto **vendável** em entrevista.

### Tasks

- [ ] **S8.1** — Completar 5 ADRs:
  - 0001-iceberg-vs-delta
  - 0002-athena-vs-emr
  - 0003-airflow-local-vs-mwaa
  - 0004-synthetic-data
  - 0005-monorepo-structure
- [ ] **S8.2** — Diagrama Excalidraw/Draw.io exportado para PNG em `docs/assets/`
- [ ] **S8.3** — GIF/screencast (asciinema ou Loom) do pipeline rodando
- [ ] **S8.4** — `dbt docs` published em GitHub Pages
- [ ] **S8.5** — `INTERVIEW_NARRATIVE.md` com scripts 5/15/30 min
- [ ] **S8.6** — `COST_ESTIMATE.md` atualizado com números reais (após primeiras execuções)
- [ ] **S8.7** — README root reescrito com:
  - Hero badge stack
  - Screenshot da arquitetura
  - Quickstart 3 comandos
  - Link para `docs/`
- [ ] **S8.8** — LinkedIn post + tweet de lançamento (opcional)

### Critério QA
- Outsider lê README e entende projeto em < 5 min
- Recrutador técnico consegue rodar localmente seguindo RUNBOOK
- GIF mostra pipeline executando do começo ao fim

### Critério Tech Lead
- 5 ADRs cobrem decisões controversas com prós/contras
- Narrativa de entrevista é coerente e defensável
- Custo final é transparente (não enganar com "free tier")

### Definition of Done
- [ ] Repo público em https://github.com/euvhmac/elt-pipeline-aws-medallion
- [ ] GitHub Pages live com `dbt docs`
- [ ] Repo aprovado por revisor externo (peer review)

---

## Backlog (Phase 2 — fora do escopo Sprint 0-8)

- Migrar para MWAA (Airflow gerenciado)
- Streaming/CDC com Kinesis ou MSK
- Lake Formation row-level security
- Multi-region/disaster recovery
- QuickSight dashboards
- Real-time analytics com Materialize ou Tinybird
- Migrar para Snowflake/BigQuery (comparativo de custos)

Cada item acima vira um issue futuro com label `phase-2`.
