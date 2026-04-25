# Stack Tecnológico

Cada componente foi escolhido por trade-off explícito (custo, complexidade, defensabilidade em entrevista). Componentes com decisões controversas têm ADR dedicado.

---

## Visão Geral por Categoria

| Categoria | Tecnologia | Versão |
|---|---|---|
| Linguagem | Python | 3.11+ |
| Gerenciador de pacotes | Poetry | 1.7+ |
| Orquestrador | Apache Airflow | 2.9+ |
| Containerização | Docker + Docker Compose | latest |
| Transformação SQL | dbt-core + dbt-athena-community | dbt 1.8+ |
| Storage | Amazon S3 | — |
| Tabela ACID | Apache Iceberg | — |
| Engine SQL | Amazon Athena (engine v3 / Trino) | — |
| Catálogo | AWS Glue Data Catalog | — |
| IaC | Terraform | 1.7+ |
| CI/CD | GitHub Actions | — |
| SQL Linter | SQLFluff | 3.0+ |
| Secrets scan | gitleaks | 8.x |
| Cloud platform | AWS | — |

---

## Categoria: Geração e Ingestão

### Python 3.11+
**Papel**: Gerador de dados sintéticos, callbacks Airflow, glue code AWS.

Por que 3.11+: melhor performance (PEP 657, faster startup) e compatibilidade plena com dbt-core 1.8+.

### Faker + PyArrow
**Papel**: Gerar dados sintéticos realistas em formato Parquet.

- **Faker**: nomes, endereços, datas, CNPJs, valores monetários
- **PyArrow**: escrita Parquet com compressão Snappy/ZSTD, particionamento Hive
- Volume: ~500 MB/dia (5 tenants × 8 datamarts × 100k registros médios)

Veja [SOURCE_DATA_GENERATOR.md](SOURCE_DATA_GENERATOR.md) para design detalhado.

### boto3
**Papel**: Cliente AWS Python — upload S3, publish SNS, leitura Secrets Manager.

---

## Categoria: Storage e Catálogo

### Amazon S3
**Papel**: Object storage subjacente para todas as 4 camadas Medallion.

- 4 buckets (bronze, silver, gold, platinum) + 1 athena-results
- Versioning habilitado
- Encryption: SSE-S3 (default)
- Lifecycle: bronze após 30d → S3 IA (Infrequent Access)

### Apache Iceberg (table format)
**Papel**: Tabelas ACID transacionais sobre Parquet.

- Suporte nativo a `MERGE`, `UPDATE`, `DELETE` no Athena engine v3
- Time travel via snapshots
- Schema evolution sem rewrite
- Hidden partitioning (não precisa filtrar manualmente)

> Decisão sobre Iceberg vs Delta: [adr/0001-iceberg-vs-delta.md](adr/0001-iceberg-vs-delta.md)

### AWS Glue Data Catalog
**Papel**: Metastore central — registra databases, tabelas, schemas.

- 5 databases: `bronze`, `silver`, `gold`, `platinum`, `seeds`
- Acessado por: Athena, dbt-athena, EMR (se usado), Glue Crawlers
- Custo: gratuito até 1M objetos/mês

---

## Categoria: Compute & Transformação

### Amazon Athena (engine v3 — Trino)
**Papel**: Engine SQL serverless para todas as queries dbt.

- Pay-per-query: ~$5 por TB escaneado
- Engine v3 = Trino (mais funções, melhor Iceberg)
- Sem cluster para gerenciar
- Limites: 30 min/query, 500 partitions/scan

> Decisão sobre Athena vs EMR: [adr/0002-athena-vs-emr.md](adr/0002-athena-vs-emr.md)

### dbt-core + dbt-athena-community
**Papel**: Camada de transformação SQL (Silver, Gold, Platinum).

- 55 modelos
- Pacotes: `dbt-utils`, `dbt-expectations`
- Estratégia incremental: `merge` (Iceberg)
- Materializações: `incremental` (Silver/Gold) + `view` (Platinum)
- Documentação automática via `dbt docs generate`

### Apache Airflow 2.x (Docker Compose local)
**Papel**: Orquestrador event-driven do pipeline.

- LocalExecutor (sem Celery — simplicidade)
- Postgres 15 backend (container)
- 2 DAGs principais + DAGs futuras
- Padrão event-driven com Airflow Datasets (2.4+)

> Decisão sobre Airflow local vs MWAA: [adr/0003-airflow-local-vs-mwaa.md](adr/0003-airflow-local-vs-mwaa.md)

---

## Categoria: Infraestrutura como Código

### Terraform 1.7+
**Papel**: Provisionar e versionar toda a infra AWS.

- 4 módulos: `s3-medallion`, `glue-catalog`, `iam-roles`, `secrets-manager`
- 2 environments: `dev`, `prd` (workspaces)
- Backend remoto: S3 + DynamoDB lock
- Provider AWS pinning

Por que Terraform e não CDK: padrão da indústria, melhor para entrevista.

### tfsec + checkov
**Papel**: Scanner de segurança Terraform no CI.

- tfsec: regras AWS-específicas
- checkov: framework-agnostic (cobre IAM, S3, etc.)

---

## Categoria: CI/CD e Qualidade

### GitHub Actions
**Papel**: Pipeline de CI/CD.

- 3 workflows: `secrets-scan`, `dbt-ci`, `terraform-ci`
- Branch protection em `main`
- Cache de dependências (pip, dbt packages)

> Veja [CI_CD.md](CI_CD.md) para detalhes.

### SQLFluff
**Papel**: Linter SQL (estilo + erros).

- Dialect: `athena` / `trino`
- Rules: aliasing obrigatório, capitalização, layout
- Pre-commit hook

### gitleaks
**Papel**: Detectar secrets em commits.

- Roda em todo PR
- Bloqueia merge se encontrar secret high severity

### dbt-checkpoint
**Papel**: Validações dbt no pre-commit.

- `check-model-has-properties-file`
- `check-source-has-tests`
- `check-model-has-description`

---

## Categoria: Observabilidade

### AWS SNS
**Papel**: Pub/sub para eventos de pipeline (failures principalmente).

- Topic único: `pipeline-alerts-${env}`
- Subscribers: Lambda Slack notifier (atual) + email (futuro)

### AWS Lambda
**Papel**: Slack notifier — recebe SNS, formata, posta.

- Runtime: Python 3.11
- Timeout: 30s
- Variáveis: `SLACK_WEBHOOK` via Secrets Manager

### CloudWatch
**Papel**: Logs + métricas + dashboards.

- Logs Lambda automáticos
- Métricas customizadas via `boto3.client('cloudwatch').put_metric_data()`
- Dashboard `elt-pipeline-aws-medallion-${env}`

---

## Categoria: Desenvolvimento Local

### Docker + Docker Compose
**Papel**: Empacotar Airflow + Postgres em ambiente reproduzível.

- Imagem oficial: `apache/airflow:2.9.x-python3.11`
- Volumes mount: `./dbt`, `./airflow/dags`, `./data-generator`
- Networks: bridge default

### Poetry
**Papel**: Gerenciador de dependências Python para data-generator e Airflow plugins.

- Lock file (`poetry.lock`) versionado
- Separação dev / prod via groups

### Make (GNU Make)
**Papel**: Atalhos para comandos comuns.

- Targets: `up`, `down`, `seed`, `dbt-run`, `dbt-test`, `clean`
- Permite UX `make all` end-to-end

---

## Stack Diagrama

```
                    ┌─────────────────────────────────┐
                    │        DESENVOLVIMENTO          │
                    │                                 │
                    │  ┌─────────┐   ┌──────────────┐ │
                    │  │ Poetry  │   │  Make        │ │
                    │  └─────────┘   └──────────────┘ │
                    │                                 │
                    │  ┌──────────────────────────┐   │
                    │  │  Docker Compose          │   │
                    │  │  ┌──────┐  ┌──────────┐  │   │
                    │  │  │Airflow│  │ Postgres │  │   │
                    │  │  └──────┘  └──────────┘  │   │
                    │  └──────────────────────────┘   │
                    └────────────┬────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────────────┐
                    │           AWS CLOUD             │
                    │                                 │
                    │  ┌─────────┐   ┌──────────────┐ │
                    │  │   S3    │   │ Glue Catalog │ │
                    │  └─────────┘   └──────────────┘ │
                    │                                 │
                    │  ┌─────────┐   ┌──────────────┐ │
                    │  │ Athena  │◄──┤ dbt-athena   │ │
                    │  └─────────┘   └──────────────┘ │
                    │                                 │
                    │  ┌─────────┐   ┌──────────────┐ │
                    │  │   SNS   │──►│   Lambda     │ │
                    │  └─────────┘   └──────────────┘ │
                    │       │                         │
                    │       ▼                         │
                    │  ┌──────────┐                   │
                    │  │CloudWatch│                   │
                    │  └──────────┘                   │
                    └─────────────────────────────────┘
                                 ▲
                                 │
                    ┌────────────┴────────────────────┐
                    │       CI/CD (GitHub)            │
                    │                                 │
                    │  ┌──────────────────────────┐   │
                    │  │  Actions:                │   │
                    │  │  • secrets-scan          │   │
                    │  │  • dbt-ci                │   │
                    │  │  • terraform-ci          │   │
                    │  └──────────────────────────┘   │
                    │                                 │
                    │  ┌──────────────────────────┐   │
                    │  │  Quality:                │   │
                    │  │  • SQLFluff              │   │
                    │  │  • tfsec / checkov       │   │
                    │  │  • gitleaks              │   │
                    │  │  • dbt-checkpoint        │   │
                    │  └──────────────────────────┘   │
                    └─────────────────────────────────┘
```

---

## Comparativo com a Stack Original (Azure)

| Categoria | Azure (original) | AWS (este projeto) |
|---|---|---|
| Storage | ADLS Gen2 + Delta | S3 + Iceberg |
| Engine SQL | Databricks SQL Warehouse | Athena |
| Catálogo | Unity Catalog | Glue Data Catalog |
| Orquestração | Airflow + Airbyte (AKS) | Airflow Docker + gerador Python |
| Adapter dbt | dbt-databricks | dbt-athena |
| IaC | Helm Charts | Terraform |
| Secrets | K8s Secrets | Secrets Manager + .env |
| Notificações | Slack/Teams direto | SNS → Lambda → Slack |
| CI/CD | Azure DevOps | GitHub Actions |

Veja [MIGRATION_FROM_AZURE.md](MIGRATION_FROM_AZURE.md) para mapeamento completo.
