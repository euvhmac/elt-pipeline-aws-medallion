# Migração Azure → AWS

Este documento mapeia, componente a componente, a arquitetura original (Azure DW corporativo) para a versão AWS deste portfólio. Cada linha tem três informações: **o que fazia**, **como era**, **como será**.

---

## Repositórios-fonte (NDA — não públicos)

A arquitetura original está distribuída em dois repositórios privados que servem como **baseline imutável** desta migração:

| Repositório-fonte | Papel original |
|---|---|
| `prj-bigdata-pipeline` | Projeto dbt corporativo (Azure Databricks) — 55 modelos Medallion |
| `prj-bigdata-pipeline-airflow` | DAGs Airflow (AKS) — orquestração Airbyte + dbt |

**Importante**: esses repositórios **não são modificados** durante a migração. Servem apenas como referência de:
- Padrões de código (estrutura de DAGs, convenções dbt)
- Estratégias de materialização incremental
- Fluxo event-driven com Airflow Datasets
- Sistema de notificações (callbacks)

Toda adaptação acontece exclusivamente neste repositório público.

---

## Mapeamento Componente a Componente

### Camada de Storage

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| Azure Data Lake Storage Gen2 | Storage subjacente | **Amazon S3** | Mesmo conceito (object storage); APIs diferentes |
| Delta Lake (formato) | Tabela ACID transacional | **Apache Iceberg** | Iceberg suportado nativamente pelo Athena (engine v3); Delta sobre Athena requer plugin externo |
| Unity Catalog | Metastore unificado | **AWS Glue Data Catalog** + Lake Formation | Glue Catalog é gratuito; permissões fine-grained via Lake Formation |
| Databricks Workspace | UI/notebooks | (ausente — não necessário) | Athena + dbt docs cumprem o papel de consulta interativa |

### Camada de Compute

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| Databricks SQL Warehouse (Pro) | Engine SQL para dbt | **Amazon Athena (engine v3 — Trino)** | Athena é serverless pay-per-query; Databricks SQL Warehouse é cluster com cold start |
| Photon engine | Acelerador de queries | (não aplicável) | Athena Trino é otimizado para Iceberg |
| Cluster Spark (Job Compute) | Notebooks/jobs ETL | (não usado) | Toda transformação é dbt; geração sintética roda local |

### Camada de Ingestão (EL)

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| Airbyte (self-hosted no AKS) | Extract & Load de ERPs | **Gerador Python (data-generator/)** | Sem ERP real para extrair; gerador sintético reproduz volume/distribuição multi-tenant |
| 35 Airbyte connections (7 emp × 5 datamarts) | Sync por empresa/datamart | DAG Python única com factory pattern | Equivalente em comportamento (1 task por combinação) |
| Connection IDs em Airflow Variables | Configuração de syncs | (não aplicável) | Substituído por config Python |

> Detalhes do gerador: [SOURCE_DATA_GENERATOR.md](SOURCE_DATA_GENERATOR.md)

### Camada de Orquestração

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| Apache Airflow 3.x (AKS, Helm) | Orquestrador | **Apache Airflow 2.x (Docker Compose local)** | Self-hosted local; mesmo motor, sem custo de gestão |
| Postgres metadata (Azure DB) | Backend Airflow | **Postgres container (Docker)** | Local; pode migrar para RDS em Phase 2 |
| Init container git-sync | Clone do repo dbt | **Volume Docker mount** | Mais simples — repo já está na máquina |
| Kubernetes Secrets | Credenciais | **AWS Secrets Manager + .env** | `.env` para dev local; Secrets Manager para prd |
| Airflow Datasets (event-driven) | Acoplamento entre DAGs | **Airflow Datasets** (mesmo padrão) | Padrão preservado integralmente |
| TaskGroups por camada (Silver/Gold/Platinum) | Granularidade na UI | **TaskGroups** (mesmo padrão) | Preservado |

### Camada de Transformação (dbt)

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| dbt-databricks adapter | Conexão dbt → Databricks | **dbt-athena adapter** | Mesma DSL; algumas funções SQL diferem (window, lateral) |
| `incremental_strategy: merge` (Delta) | Update + insert | **`incremental_strategy: merge`** (Iceberg) | Iceberg suporta MERGE nativo no Athena |
| `dbt_utils.generate_surrogate_key` | PKs sintéticas | **mesmo** | Funciona idêntico |
| `dbt_expectations` | Testes avançados | **mesmo** | Compatível com Athena |
| profiles.yml gerado em runtime (BashOperator) | Credenciais Databricks | **profiles.yml com `aws_profile: default`** | AWS credentials via boto3; mais simples |

### Camada de Observabilidade

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| Slack/Teams via webhooks (callbacks Airflow) | Alertas | **SNS topic → Lambda → Slack** | Desacoplado; permite múltiplos consumers do SNS |
| Email notifier (SMTP) | Alertas email | **SNS subscription** | SNS suporta email nativamente |
| Airflow logs (PV no AKS) | Logs persistentes | **Logs locais + opcional CloudWatch** | Local para dev; CloudWatch se exportar |
| (não havia) | Dashboards de custo | **CloudWatch Dashboard** | Adicionado no projeto novo |

### Infraestrutura como Código

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| Helm Charts (values-dev/prd.yaml) | Deploy Airflow | **Docker Compose** | Local — sem K8s |
| (não havia IaC explícito) | Infra Azure manual | **Terraform (4 módulos)** | Adicionado: melhor prática moderna |
| Azure DevOps Pipelines | CI/CD | **GitHub Actions** | Workflows YAML equivalentes |

### Multi-tenancy

| Componente Azure | Função | Componente AWS | Diferença Operacional |
|---|---|---|---|
| N unidades de negócio reais do grupo (anonimizadas) | Tenants reais | **5 tenants anonimizados** (`unit_01..unit_05`) | Subset reduzido; nomes substituídos |
| Schema por empresa em Bronze (`bronze__<unit_name>`) | Isolamento físico | **Particionamento por `tenant_id` em S3 + tabela única** | Mais simples; evita N tabelas separadas |
| `id_<sistema_origem>` como source key | ID do ERP origem | **`id_erp_internal`** | Sanitizado — nome do ERP removido |

---

## Regras de Migração

Durante a Sprint 4 (migração dos modelos dbt), as seguintes regras se aplicam:

### Funções SQL — Equivalências

| Databricks SQL | Athena (Trino) | Observação |
|---|---|---|
| `current_timestamp()` | `current_timestamp` (sem parens) | — |
| `to_date(col, fmt)` | `date_parse(col, fmt)` | Trino usa Java SimpleDateFormat |
| `from_unixtime(ts)` | `from_unixtime(ts)` | Compatível |
| `regexp_extract` | `regexp_extract` | Compatível |
| `array_contains(arr, val)` | `contains(arr, val)` | Renomear |
| `lateral view explode(arr)` | `CROSS JOIN UNNEST(arr) AS t(col)` | Reescrever |
| `MERGE INTO` (Delta) | `MERGE INTO` (Iceberg via Athena) | Sintaxe similar |

### Configurações dbt — Equivalências

```yaml
# Antes (dbt-databricks)
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    file_format='delta',
    on_schema_change='append_new_columns'
) }}

# Depois (dbt-athena)
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    table_type='iceberg',
    on_schema_change='append_new_columns'
) }}
```

### profiles.yml — Equivalências

```yaml
# Antes (Databricks)
default:
  type: databricks
  host: <DATABRICKS_HOST>
  http_path: <DATABRICKS_HTTP_PATH>
  token: <DATABRICKS_TOKEN>
  catalog: <UNITY_CATALOG>
  schema: <SCHEMA>

# Depois (Athena)
default:
  type: athena
  s3_staging_dir: s3://elt-pipeline-aws-medallion-athena-results-dev/
  region_name: us-east-1
  database: silver
  aws_profile_name: default
  threads: 8
```

---

## Referências cruzadas

- **Decisão de Iceberg sobre Delta**: [adr/0001-iceberg-vs-delta.md](adr/0001-iceberg-vs-delta.md)
- **Decisão de Athena sobre EMR**: [adr/0002-athena-vs-emr.md](adr/0002-athena-vs-emr.md)
- **Decisão de Airflow local sobre MWAA**: [adr/0003-airflow-local-vs-mwaa.md](adr/0003-airflow-local-vs-mwaa.md)
- **Decisão de gerador sintético**: [adr/0004-synthetic-data.md](adr/0004-synthetic-data.md)
