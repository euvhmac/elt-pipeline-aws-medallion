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

## Sprint 4 — Camada de Transformação (dbt-athena) ✅

### Objetivo (executado)
Provar end-to-end o stack dbt-athena-community + Iceberg + Silver→Gold star schema, usando o **datamart Comercial** como vertical fatia. Os demais 7 datamarts replicam o mesmo padrão e ficam como backlog explicito (Sprint 4.5+).

### Status: DONE — `dbt build` PASS=67 ERROR=0 em 3min10s

### Tasks executadas

- [x] **S4.1** — `dbt-athena-community~=1.9.0` (resolveu para 1.10.0) em `pyproject.toml`
- [x] **S4.2** — `dbt_project.yml`:
  - `+table_type: iceberg`
  - `+incremental_strategy: merge`
  - `+on_schema_change: append_new_columns`
  - `+partitioned_by: ['tenant_id']`
- [x] **S4.3** — `dbt/models/sources/sources.yml` declarando 23 sources Bronze
- [x] **S4.4** — **5 modelos Silver** (datamart Comercial, incremental merge + dedup row_number):
  - `silver_dw_clientes`, `silver_dw_vendedores`, `silver_dw_produtos`,
    `silver_dw_vendas`, `silver_dw_itens_pedido`
- [x] **S4.5** — **5 modelos Gold** (Kimball star schema):
  - Dims: `dim_calendrio` (gerada via Jinja, 1.461 dias), `dim_clientes`, `dim_produtos`, `dim_vendedores`
  - Fact: `fct_vendas` (incremental merge, FK surrogate keys, dedup)
- [x] **S4.6** — Testes:
  - 9 not_null + 5 unique + 4 relationships + 1 accepted_values + 4 unique_combination_of_columns + 1 singular test (`assert_fct_vendas_total_consistente`)
- [x] **S4.7** — Macro `generate_schema_name` para usar schemas Glue absolutos (`silver_dev`, `gold_dev`)

### Resultado real (validado contra AWS)

```
Geracao de dados Bronze: 7 dias x 3 tenants = 241.144 linhas em 23 tabelas
dbt build (full-refresh): PASS=67 ERROR=0 em 3min10s
Counts apos build:
  fct_vendas    = 8.525 itens
  dim_clientes  = 7.400 clientes
  dim_calendrio = 1.461 dias (2024-2027)
```

### Decisoes documentadas

1. **Escopo reduzido vs roadmap original (55 modelos)**: implementamos a fatia vertical do datamart Comercial (5 silver + 5 gold), provando o padrao end-to-end. Os outros 7 datamarts replicam o mesmo template.
2. **Dedup via `row_number()`**: gerador produz duplicatas em range historico (mesmo seed gera mesmos IDs por dia). Resolvido com `qualify` window function nas Silver.
3. **Macro `generate_schema_name`**: usar schemas Glue absolutos em vez do default dbt `target_schema_custom_schema`. Necessario porque ja temos dbs `silver_dev`, `gold_dev` provisionados via Terraform Sprint 2.

### Backlog explicito (Sprint 4.5+)

- Modelos Silver e Gold dos demais 7 datamarts (financeiro, controladoria, logistica, suprimentos, corporativo, industrial, contabilidade)
- 9 modelos Platinum (DRE por unidade, controle inadimplentes)
- `dbt docs generate` + upload S3 + GitHub Pages
- `dbt source freshness` em sources.yml
- Upload manifest.json/run_results.json para `s3://...-dbt-artifacts-dev/`
- [ ] `dbt docs` publicado em GitHub Pages

---

## Sprint 5 — Orquestração (Airflow Local) ✅

### Objetivo (executado)
Airflow orquestra o pipeline end-to-end: `dag_synthetic_source` (Bronze) → trigger event-driven via Dataset → `dag_dbt_aws_detailed` (Silver+Gold+Tests).

### Status: DONE

### Tasks executadas

- [x] **S5.1** — `dag_synthetic_source` refinada: publica `Dataset("s3://elt-pipeline-bronze-dev/")` como `outlet` ao concluir `validate_athena`
- [x] **S5.2** — DAG `dag_dbt_aws_detailed`:
  - `schedule=[BRONZE_DATASET]` (event-driven, sem cron)
  - Task inicial `dbt_deps`
  - `TaskGroup silver_layer`: 5 BashOperators (1 por modelo silver_dw_*)
  - `TaskGroup gold_layer`: subgrupos `dimensions` (4 dims) → `facts` (fct_vendas)
  - `TaskGroup tests_layer`: `dbt test --select <model>` por modelo
  - `max_active_tasks=8` (limite paralelismo Athena)
- [x] **S5.3** — `airflow/dags/utils/callbacks.py`:
  - `task_failure_alert` (logging estruturado JSON; SNS/Slack vai na Sprint 6)
  - `task_success_alert` (uso seletivo)
- [x] **S5.4** — `docker-compose.yml`:
  - `_PIP_ADDITIONAL_REQUIREMENTS` adiciona `dbt-core==1.10.0` + `dbt-athena-community==1.10.0`
  - `DBT_PROFILES_DIR` e `DBT_PROJECT_DIR` apontam para `/opt/airflow/dbt`
- [x] **S5.5** — Volumes Docker já estavam corretos (`../dbt`, `../data-generator` montados)

### Decisões documentadas

1. **Granularidade 1 task = 1 modelo**: facilita retry isolado e visibilidade no Grid View. Trade-off: mais overhead Airflow vs menos blast radius por falha.
2. **Dataset event-driven em vez de TriggerDagRunOperator**: padrão moderno Airflow 2.4+, desacopla DAGs e permite múltiplos consumidores futuros (ex: ML pipeline reagindo a Gold).
3. **`dbt deps` como task isolada**: garante `packages.yml` instalado antes de qualquer `dbt run`. Cacheável entre runs (volume mount).
4. **Callbacks só com logging na Sprint 5**: Sprint 6 plugará SNS publish; mantém escopo enxuto.

### Critério QA — RESULTADO
- ✅ `ruff check airflow/dags/` → All checks passed
- ✅ `python -m py_compile` em ambas DAGs → exit 0
- ✅ Import `from airflow.datasets import Dataset` validado (Airflow 2.9)
- ⏳ Smoke E2E real (trigger → Dataset → dbt build) será exercitado na próxima execução do Compose local

### Definition of Done
- [x] Ambas DAGs com sintaxe válida e lint clean
- [x] PR `feat/sprint-5-airflow-dbt → develop` mergeado
- [ ] Backfill manual exercitado no Airflow UI (deferido para próxima sessão prática)

---

## Sprint 6 — Observabilidade & Notificações ✅

### Objetivo (executado)
Fechar o loop operacional: falhas no Airflow chegam ao Slack em < 60s via SNS → Lambda → webhook.
**Não** implementa dashboards CloudWatch nem upload de dbt artifacts (deferido para Sprint 8 / backlog) — foco em ROI alto e narrativa de entrevista clara.

### Status: DONE — PR #10 mergeado

### Tasks executadas

- [x] **S6.1** — Módulo Terraform `infra/modules/sns-lambda-slack/`:
  - `aws_sns_topic` `pipeline-alerts`
  - `aws_lambda_function` `slack-notifier` (runtime python3.11, inline zip via `archive_file`)
  - `aws_iam_role` Lambda + `AWSLambdaBasicExecutionRole` + policy custom (`secretsmanager:GetSecretValue` apenas no ARN do webhook)
  - `aws_sns_topic_subscription` + `aws_lambda_permission` (SNS → Lambda)
- [x] **S6.2** — `lambda/slack_notifier/handler.py`:
  - Lê webhook do Secrets Manager (cache em memória entre invocações)
  - Formata Slack Block Kit (dag_id, task_id, try_number, exception, log_url)
  - POST via `urllib` (zero deps externas → zip nativo de KB)
- [x] **S6.3** — Wire no `infra/envs/dev/main.tf`:
  - Chama módulo passando `slack_secret_arn` do `secrets_manager`
  - Outputs: `pipeline_alerts_topic_arn` + `slack_notifier_lambda`
- [x] **S6.4** — `airflow/dags/utils/callbacks.py`:
  - `task_failure_alert` publica em SNS via `boto3.client("sns").publish(...)`
  - ARN via env var `PIPELINE_ALERTS_TOPIC_ARN` (configurada no docker-compose)
  - **Graceful degradation**: se ARN vazio, apenas loga (sem quebrar a DAG)
- [x] **S6.5** — `.env.example` documentado com variável + instruções de ativação no PR body

### Decisões documentadas

1. **Sem CloudWatch Dashboard / dbt artifacts upload na S6**: deferido para Sprint 8 / backlog. ROI alto = alerta de falha (loop operacional fechado).
2. **Sem DLQ no Lambda**: SNS já tem retry automático; volume baixo não justifica complexidade extra.
3. **`urllib` em vez de `requests`**: zero deps = zip de KB, sem layer/build pipeline.
4. **Cache em memória do webhook**: container reuse do Lambda mantém o secret carregado, reduz round-trips ao Secrets Manager (latência + custo).
5. **Graceful degradation no callback**: dev local sem AWS configurada continua funcionando; SNS só "liga" quando env var existe.

### Backlog explicito (deferido)
- CloudWatch Dashboard (`elt-pipeline-overview`)
- Upload `manifest.json`/`run_results.json` → S3 `dbt-artifacts`
- Logs Airflow → CloudWatch (logs do container já ficam em `./logs`)
- Lambda DLQ (justificado: SNS já tem retry; baixo volume)
- RUNBOOK: procedimento de rotação de webhook + teste E2E

### Critério QA — RESULTADO
- ✅ `ruff check lambda/ airflow/dags/` → All checks passed
- ✅ `terraform fmt -recursive` aplicado
- ✅ `terraform validate` em `infra/envs/dev` → Success! The configuration is valid
- ✅ `python -m py_compile` em handler.py + callbacks.py → exit 0
- ⏳ `terraform apply` real + smoke E2E (forçar falha → Slack) deferido para próxima sessão prática

### Critério Tech Lead — RESULTADO
- ✅ Alerta inclui: `dag_id`, `task_id`, `run_id`, `try_number`, `exception`, `log_url`
- ✅ Lambda timeout 10s, memória 128 MB (mínimo viável)
- ✅ Custo total observabilidade ~$0/mês (SNS volume dev + Lambda free tier + secret webhook $0.40/mês já existente)
- ✅ Webhook apenas em Secrets Manager — nunca em variável Terraform / código
- ✅ IAM least-privilege: Lambda só pode ler **aquele** secret específico (não `*`)

### Definition of Done
- [x] PR `feat/sprint-6-observabilidade → develop` mergeado (#10)
- [x] `terraform validate` passou
- [x] Callback publica em SNS quando `PIPELINE_ALERTS_TOPIC_ARN` está setado; degrada para apenas-log quando não está
- [ ] `terraform apply` real + smoke E2E (deferido para sessão prática)

---

## Sprint 7 — CI/CD & Quality Gates ✅

### Objetivo (executado)
Bloquear merges com problemas via GitHub Actions; padronizar lint/format local com pre-commit. Escopo enxuto: validar/lint sem custo AWS (sem `dbt build` real, sem `terraform plan` autenticado).

### Status: DONE

### Tasks executadas

- [x] **S7.1** — `.github/workflows/secrets-scan.yml`:
  - `gitleaks/gitleaks-action@v2` em todo PR + push em `main`/`develop`
  - `fetch-depth: 0` para escanear histórico completo
- [x] **S7.2** — `.github/workflows/dbt-ci.yml`:
  - Trigger em PR alterando `dbt/**`
  - Steps: `pip install dbt-core 1.10 + dbt-athena 1.10 + sqlfluff` → `dbt deps` → `dbt parse` (vars dummy, sem conexão Athena) → `sqlfluff lint` (`continue-on-error` warn-only)
  - **Sem `dbt build`** no CI (custo AWS + secrets); promovido a backlog quando houver state defer real
- [x] **S7.3** — `.github/workflows/terraform-ci.yml`:
  - Trigger em PR alterando `infra/**`
  - Steps: `terraform fmt -check -recursive` → `init -backend=false` → `validate` → `tfsec` (soft_fail)
  - **Sem `terraform plan`** no CI (precisaria credentials AWS); deferido para auth via OIDC quando necessário
- [x] **S7.4** — `.sqlfluff`:
  - Dialect `athena`, templater `jinja`
  - Lowercase keywords/identifiers/functions
  - Macros path apontando para `dbt/macros`
- [x] **S7.5** — `.pre-commit-config.yaml`:
  - pre-commit-hooks (trailing-whitespace, end-of-file, yaml, large-files, merge-conflict, private-key)
  - gitleaks
  - ruff + ruff-format
  - terraform_fmt + terraform_validate
- [x] **S7.6** — Branch protection rules: **deferido para configuração manual no GitHub Settings** (requer admin UI, não dá para automatizar via repo)

### Decisões documentadas (anti over-engineering)

1. **`dbt build` fora do CI**: rodar dbt real exige IAM + Athena + scan de bytes (custo). Solução = `dbt parse` valida sintaxe + refs + manifest sem conectar. Build real fica para Airflow.
2. **`terraform plan` fora do CI**: precisaria OIDC + role-assume. `validate` + `fmt` + `tfsec` cobrem 80% dos bugs sem abrir credenciais. Plan/apply ficam locais até haver mais contribuidores.
3. **`tfsec` com `soft_fail: true`**: warn-only inicial; aprender quais alertas matam. Promover a hard-fail depois de baseline limpo.
4. **`sqlfluff` com `continue-on-error`**: warn-only até cleanup de modelos legados Sprint 4. Promover a hard-fail na Sprint 8.
5. **dbt-checkpoint não incluído no pre-commit**: menos crítico que ruff/sqlfluff e adiciona deps Python pesadas. Avaliar futuro.

### Backlog explicito (deferido)

- Branch protection rules em `main` e `develop` (config manual GitHub UI)
- README badges (CI status)
- `CONTRIBUTING.md` ampliado com processo PR detalhado
- `dbt build --select state:modified+` com defer para state em S3 (Sprint 8+)
- `terraform plan` com OIDC role-assume + comentário automatico no PR
- Promover `tfsec` e `sqlfluff` de warn para hard-fail
- `checkov` (redundante com `tfsec` por enquanto)

### Critério QA — RESULTADO
- ✅ Workflows YAML validados (`yaml.safe_load` em todos os 5)
- ✅ `.sqlfluff` parseável
- ✅ `.pre-commit-config.yaml` válido
- ⏳ Demo de PR bloqueado por cada gate fica para próxima sessão (precisa abrir PR com violação proposital)

### Critério Tech Lead — RESULTADO
- ✅ Cache de pip configurado (`actions/cache@v4` com chave em `pyproject.toml`)
- ✅ `paths` filter em todos workflows (não roda dbt-ci quando só infra muda, etc.)
- ✅ Permissões mínimas: `permissions: contents: read, pull-requests: write` apenas onde precisa
- ✅ Custo CI: $0 (GitHub Actions free para repo público)

### Definition of Done
- [x] PR `feat/sprint-7-cicd → develop` mergeado
- [x] 5 arquivos novos criados (3 workflows + 2 configs)
- [ ] Branch protection configurada manualmente no GitHub (próxima sessão)
- [ ] PR de teste com violação proposital validando bloqueio (próxima sessão)

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
