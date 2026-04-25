# Sprint Roadmap

Plano de execução em 8 sprints, com critérios de aceite QA + Tech Lead por sprint. Cada sprint produz artefatos verificáveis e tem **definition of done** explícito.

---

## Visão Geral

| Sprint | Foco | Duração estimada |
|---|---|---|
| **Sprint 0** | Preparação & Documentação Inicial | 1 dia |
| **Sprint 1** | Fundação Local (Dev Environment) | 2-3 dias |
| **Sprint 2** | Infraestrutura AWS (Terraform) | 2 dias |
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

- [ ] **S1.1** — Estrutura monorepo:
  ```
  ├── dbt/                  (mover modelos atuais para cá)
  ├── airflow/
  ├── data-generator/
  ├── infra/
  └── docs/  (já existe)
  ```
- [ ] **S1.2** — `airflow/docker-compose.yml`:
  - Airflow 2.x (LocalExecutor)
  - Postgres 15 metadata
  - Redis (opcional)
  - Volume mounts: `./dags`, `../dbt`, `../data-generator`
- [ ] **S1.3** — `data-generator/`:
  - Schema dataclasses por datamart
  - Geradores Faker (clientes, vendas, financeiro, logística...)
  - Saída: Parquet local em `data-generator/output/`
- [ ] **S1.4** — `dbt/profiles_example.yml` para Athena:
  ```yaml
  default:
    type: athena
    s3_staging_dir: s3://...
    region_name: us-east-1
  ```
- [ ] **S1.5** — `Makefile` com targets:
  - `make up` / `make down`
  - `make seed` (gera Parquet local)
  - `make dbt-run` / `make dbt-test`
  - `make logs`
- [ ] **S1.6** — `pyproject.toml` com Poetry: `data-generator/`, `airflow/dags/utils/`

### Critério QA
- Clone limpo + `cp .env.example .env` + `make up` → Airflow UI em http://localhost:8080
- `make seed` produz 40 arquivos Parquet (5 tenants × 8 datamarts)
- Schemas validam com `pyarrow.parquet.read_schema()`

### Critério Tech Lead
- Volume mounts permitem editar dbt sem rebuild de imagem
- Logs estruturados (JSON via Python `logging`)
- `.env.example` documenta todas as variáveis necessárias
- Ausência de hardcoded paths (uso de `pathlib.Path`)

### Definition of Done
- [ ] README.md root tem seção "Quickstart" funcional
- [ ] CI verifica `docker compose config` (validação YAML)
- [ ] Push da Sprint 1 com commit message convencional

---

## Sprint 2 — Infraestrutura AWS (Terraform)

### Objetivo
Provisionar infra AWS via Terraform, com módulos reutilizáveis e backend remoto.

### Tasks

- [ ] **S2.1** — Bootstrap backend (manual única vez):
  - S3 bucket para state: `elt-pipeline-tfstate-${aws_account_id}`
  - DynamoDB table para lock: `elt-pipeline-tfstate-lock`
- [ ] **S2.2** — Módulo `infra/modules/s3-medallion/`:
  - 4 buckets (bronze/silver/gold/platinum) + 1 athena-results
  - Versioning, encryption, lifecycle (mover Bronze para IA após 30d)
- [ ] **S2.3** — Módulo `infra/modules/glue-catalog/`:
  - 5 databases (bronze, silver, gold, platinum, seeds)
  - Permissões básicas
- [ ] **S2.4** — Módulo `infra/modules/iam-roles/`:
  - Role para dbt-athena (least-privilege: S3 read/write + Glue + Athena)
  - Role para Lambda slack-notifier
- [ ] **S2.5** — Módulo `infra/modules/secrets-manager/`:
  - Secret `slack-webhook-url`
  - Secret `dbt-athena-credentials` (placeholder)
- [ ] **S2.6** — `infra/envs/dev/` e `infra/envs/prd/`:
  - `main.tf` chamando módulos
  - `variables.tf` + `terraform.tfvars` (gitignored)
  - `versions.tf` com provider AWS pinning

### Critério QA
- `terraform fmt -check -recursive` passa
- `terraform validate` em todos os módulos
- `tfsec` zero high severity
- `terraform plan` em dev cria infra esperada (revisão de plan output)

### Critério Tech Lead
- Módulos não dependem de variáveis hardcoded (tudo parametrizado)
- Backend remoto configurado e testado
- `terraform apply` em < 3 min em dev
- Custo estimado < $1/mês com infra ociosa

### Definition of Done
- [ ] `terraform apply -workspace=dev` executa sem erros
- [ ] `aws s3 ls` lista os 5 buckets
- [ ] `aws glue get-databases` retorna 5 databases
- [ ] Documentação `infra/README.md` com instruções

---

## Sprint 3 — Camada de Ingestão (Bronze)

### Objetivo
Pipeline de ingestão funcional: gerador local → S3 Bronze → tabelas Athena navegáveis.

### Tasks

- [ ] **S3.1** — Refatorar `data-generator/` para upload S3 (boto3)
- [ ] **S3.2** — Particionamento Hive: `tenant_id=unit_01/year=2025/month=04/day=25/`
- [ ] **S3.3** — DDL declarativo Glue (Terraform `aws_glue_catalog_table` ou ALTER TABLE ADD PARTITION via Athena)
- [ ] **S3.4** — DAG `airflow/dags/dag_synthetic_source.py`:
  - Tasks: `generate_data` → `upload_s3` → `register_partitions` → `validate_counts`
  - Outlets: 8 Airflow Datasets (por datamart)
- [ ] **S3.5** — Validação: query Athena `SELECT count(*) FROM bronze.fct_vendas_unit_01`
- [ ] **S3.6** — Schema evolution: novos campos automáticos via Iceberg (Sprint 4)

### Critério QA
- 40 tabelas Bronze acessíveis via Athena
- Counts entre Pandas (geração) e Athena query são idênticos
- Particionamento correto: `MSCK REPAIR TABLE` ou partition projection funciona
- Custo S3 < $0.10/dia em volume de teste

### Critério Tech Lead
- Geração e upload são idempotentes (re-run mesmo dia não duplica)
- Logs incluem: tenant, datamart, registros gerados, tempo, tamanho Parquet
- Erros de upload têm retry exponential backoff (boto3 default)
- Particionamento permite query eficiente (predicate pushdown)

### Definition of Done
- [ ] DAG `dag_synthetic_source` aparece no Airflow UI
- [ ] Trigger manual da DAG completa em < 5 min
- [ ] Athena query retorna dados esperados
- [ ] dbt source freshness configurado em `dbt/sources.yml`

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
