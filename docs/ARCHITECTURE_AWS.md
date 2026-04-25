# Arquitetura AWS — ELT Pipeline Medallion

## Visão Macro

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       FONTE SIMULADA (LOCAL)                                │
│                                                                             │
│  data-generator/  (Python + Faker + PyArrow)                               │
│  Gera Parquet para 5 tenants × 8 datamarts                                 │
│                                                                             │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │ upload (boto3)
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AWS — STORAGE LAYER                                │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │  S3 — 4 buckets (Medallion)                                       │    │
│   │  • s3://${proj}-bronze-${env}/   raw zone (Parquet particionado)  │    │
│   │  • s3://${proj}-silver-${env}/   Iceberg tables (cleaned)         │    │
│   │  • s3://${proj}-gold-${env}/     Iceberg tables (star schema)     │    │
│   │  • s3://${proj}-platinum-${env}/ Iceberg tables (consumo BI)      │    │
│   │  • s3://${proj}-athena-results-${env}/  query results             │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │  AWS Glue Data Catalog                                            │    │
│   │  • database: bronze   (40 tabelas externas)                       │    │
│   │  • database: silver   (30 tabelas Iceberg)                        │    │
│   │  • database: gold     (16 tabelas Iceberg)                        │    │
│   │  • database: platinum ( 9 views/tabelas Iceberg)                  │    │
│   │  • database: seeds    (referenciais estáticos)                    │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │ queries SQL
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                   AWS — COMPUTE LAYER (SERVERLESS)                          │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │  Amazon Athena (engine v3 — Trino)                                │    │
│   │  Pay-per-query (~$5/TB scanned)                                   │    │
│   │  Suporta Iceberg nativo: MERGE, UPDATE, DELETE                    │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │ dbt-athena adapter
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ORQUESTRAÇÃO (DOCKER LOCAL)                              │
│                                                                             │
│   ┌───────────────────────────────────────────────────────────────────┐    │
│   │  Apache Airflow 2.x  (docker-compose)                             │    │
│   │  • Postgres (metadata)                                            │    │
│   │  • Webserver + Scheduler + Triggerer + Worker                     │    │
│   │  • Volume mount: dbt/  airflow/dags/                              │    │
│   │                                                                   │    │
│   │  DAGs:                                                            │    │
│   │  • dag_synthetic_source     (gera + upload Bronze)               │    │
│   │  • dag_dbt_aws_detailed     (orquestra dbt — event-driven)       │    │
│   │                                                                   │    │
│   │  Conexão AWS: AWS_PROFILE no .env                                 │    │
│   └───────────────────────────────────────────────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────┬───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    OBSERVABILIDADE & ALERTAS                                │
│                                                                             │
│  CloudWatch Dashboard       SNS topic            Lambda                     │
│  • Athena queries           pipeline-alerts ───► slack-notifier ──► Slack  │
│  • S3 storage / costs                                                       │
│  • dbt artifacts (S3)                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Fluxo de Dados Detalhado

### 1. Geração (Source Simulator)

```
Python data-generator
    │
    ├─► Para cada tenant em [unit_01..unit_05]:
    │   ├─► Para cada datamart em [comercial, financeiro, ...]:
    │   │   ├─► Gera N registros com Faker + lógica de negócio
    │   │   ├─► Aplica seeds para referência (calendário, DRE, contas)
    │   │   └─► Salva Parquet local + upload S3 Bronze
    │   │
    │   └─► Particionamento: tenant=unit_01/year=2025/month=01/day=15/file.parquet
    │
    └─► Emite Airflow Dataset por datamart (event-driven trigger downstream)
```

### 2. Camada Bronze — Raw Zone

```
S3 Bronze (Parquet, particionado)
    │
    ├─► Glue Data Catalog (CREATE EXTERNAL TABLE via DDL Terraform)
    │
    └─► Acessível via Athena: SELECT * FROM bronze.customer_unit_01
```

### 3. Camada Silver — Cleaning & Standardization

```
dbt models/silver/  (30 modelos)
    │
    ├─► Padroniza nomes de colunas
    ├─► Trata nulls e tipos (CAST + COALESCE)
    ├─► Unifica multi-tenant: UNION dos 5 tenants em um modelo unificado
    ├─► Remove duplicatas (ROW_NUMBER + WHERE rn=1)
    │
    └─► Materializado como Iceberg incremental_strategy='merge'
        s3://...-silver-${env}/silver_dw_<modelo>/
```

### 4. Camada Gold — Star Schema

```
dbt models/gold/  (16 modelos)
    │
    ├─► Dimensions (8): calendário, clientes, produtos, empresas, vendedores...
    ├─► Facts (6): vendas, faturamento, devolução, financeiro, lançamentos...
    ├─► DRE (2): contábil + gerencial
    │
    └─► Materializado como Iceberg
        Surrogate keys via dbt_utils.generate_surrogate_key
```

### 5. Camada Platinum — Business-Ready Views

```
dbt models/platinum/  (9 modelos)
    │
    ├─► DRE por unidade (5 modelos consolidados)
    ├─► DRE Gerencial por unidade
    ├─► Controle de inadimplentes
    ├─► Estruturas DRE auxiliares
    │
    └─► Materializado como view (consumo BI direto via Athena)
```

## Diagrama de Orquestração (Event-Driven)

```
                     ┌──────────────────────────────────────────────┐
                     │  Airflow Datasets — comunicação entre DAGs   │
                     └──────────────────────────────────────────────┘

Schedule: 06:00 UTC
    │
    ▼
┌────────────────────────────────────────────────────────────────┐
│ dag_synthetic_source                                           │
│                                                                │
│  generate_data ──► upload_s3 ──► validate_counts              │
│                                       │                        │
│                                       ▼ outlets=               │
│                                  [DATASET_BRONZE_COMERCIAL,    │
│                                   DATASET_BRONZE_FINANCEIRO,   │
│                                   DATASET_BRONZE_LOGISTICA,    │
│                                   ... (8 datasets)]            │
└────────────────────────────────────────────────────────────────┘
                              │
                  (todos 8 datasets atualizados)
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ dag_dbt_aws_detailed  schedule=[8 datasets]                    │
│                                                                │
│  dbt_deps                                                      │
│      │                                                         │
│      ▼                                                         │
│  dbt_seed                                                      │
│      │                                                         │
│      ▼                                                         │
│  silver_layer (TaskGroup — 30 tasks paralelas, max 8 ativas)  │
│      │                                                         │
│      ▼                                                         │
│  gold_layer (TaskGroup — 16 tasks paralelas)                  │
│      │                                                         │
│      ▼                                                         │
│  platinum_layer (TaskGroup — 9 tasks)                         │
│      │                                                         │
│      ▼                                                         │
│  dbt_test                                                      │
│      │                                                         │
│      ▼                                                         │
│  upload_dbt_artifacts (S3)                                     │
└────────────────────────────────────────────────────────────────┘
```

## Diagrama de Observabilidade

```
┌─────────────────────────────────────────────────────────────┐
│                    AIRFLOW                                   │
│                                                              │
│  Task fails → on_failure_callback                            │
│      │                                                       │
│      ▼                                                       │
│  utils/callbacks.task_failure_alert(context)                 │
│      │                                                       │
│      ▼                                                       │
│  boto3 SNS publish ───┐                                      │
└────────────────────────┼─────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  AWS — SNS topic: pipeline-alerts                           │
│      │                                                       │
│      ▼                                                       │
│  Lambda: slack-notifier (Python)                             │
│      │                                                       │
│      ├─► Parse SNS message                                   │
│      ├─► Format Slack blocks                                 │
│      └─► POST webhook                                        │
└─────────────────────────────────────┬───────────────────────┘
                                      │
                                      ▼
                          Slack #data-alerts channel
```

## Diagrama de CI/CD

```
GitHub Pull Request
    │
    ├─► .github/workflows/secrets-scan.yml
    │       gitleaks detect → bloqueia se encontrar secret
    │
    ├─► .github/workflows/dbt-ci.yml  (se mudou em dbt/**)
    │       1. dbt deps
    │       2. dbt parse
    │       3. dbt compile
    │       4. dbt build --select state:modified+ (com defer ao prd)
    │       5. SQLFluff lint
    │       6. dbt-checkpoint hooks
    │
    └─► .github/workflows/terraform-ci.yml  (se mudou em infra/**)
            1. terraform fmt -check
            2. terraform validate
            3. terraform plan -no-color
            4. tfsec
            5. checkov
            6. Comment plan output em PR

Status checks obrigatórios → branch protection on main
```

## Estados de Materialização por Camada

| Camada | Estratégia dbt | Motivo |
|---|---|---|
| Seeds | `seed` (CSV) | Dados estáticos |
| Bronze | `external_table` (Glue DDL) | Raw, particionado, evita custo Iceberg |
| Silver | `incremental` + `merge` (Iceberg) | Volumes médios, lookback window de N dias |
| Gold | `incremental` + `merge` (Iceberg) | Facts incrementais; dims com `table` |
| Platinum | `view` | Consumo BI, sem custo de armazenamento |

## Limites e Trade-offs

| Aspecto | Limite Aceitável |
|---|---|
| Latência fim-a-fim | ~30 min (batch diário 06:00 UTC) |
| Volume diário simulado | ~500 MB Parquet (5 tenants × 8 datamarts) |
| Custo mensal AWS | $5–15 (free tier first year) |
| Disponibilidade | Dev only — não há SLA, é portfolio |
| Backup/DR | Versionamento S3 + Iceberg time travel |

Para detalhes da escolha de cada componente, veja:
- [adr/0001-iceberg-vs-delta.md](adr/0001-iceberg-vs-delta.md)
- [adr/0002-athena-vs-emr.md](adr/0002-athena-vs-emr.md)
- [adr/0003-airflow-local-vs-mwaa.md](adr/0003-airflow-local-vs-mwaa.md)
