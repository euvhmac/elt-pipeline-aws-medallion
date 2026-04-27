# ELT Pipeline AWS — Medallion Architecture

> Plataforma analítica **multi-tenant** em AWS com arquitetura **Medallion** de 4 camadas (Bronze → Silver → Gold → Platinum), orquestrada por **Airflow**, transformada em **dbt + Apache Iceberg** sobre **Amazon Athena**, infra 100% como código em **Terraform**.

[![CI: secrets-scan](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/secrets-scan.yml/badge.svg)](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/secrets-scan.yml)
[![CI: dbt](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/dbt-ci.yml/badge.svg)](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/dbt-ci.yml)
[![CI: terraform](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/terraform-ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![dbt](https://img.shields.io/badge/dbt--athena-1.10-orange)](https://www.getdbt.com/)
[![Airflow](https://img.shields.io/badge/Airflow-2.9-017CEE)](https://airflow.apache.org/)
[![Terraform](https://img.shields.io/badge/Terraform-1.7+-7B42BC)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20Athena%20%7C%20Glue-FF9900)](https://aws.amazon.com/)
[![Python](https://img.shields.io/badge/Python-3.11-3776AB)](https://www.python.org/)
[![Apache Iceberg](https://img.shields.io/badge/Apache%20Iceberg-enabled-007EC6)](https://iceberg.apache.org/)

---

## O que é este projeto

Reconstrução completa em **AWS** de uma plataforma analítica multi-tenant originalmente em **Azure Databricks + Delta Lake**. Preserva 100% da lógica de negócio — 8 datamarts, 45 modelos dbt, star schema Kimball, 5 unidades de negócio — com uma redução de custo de **~99%** (~$800/mês → ~$6/mês).

O projeto demonstra engenharia de dados **production-grade** end-to-end: ingestão sintética, transformação incremental com Iceberg, orquestração event-driven, observabilidade via CloudWatch + Slack, e CI/CD com GitHub Actions.

> **Status atual**: ✅ Todas as 9 sprints entregues — plataforma completa e operacional.

---

## Impacto em Números

| Métrica | Valor |
|---|---|
| Modelos dbt | **45** (21 Silver + 18 Gold + 6 Platinum) |
| Datamarts | 8 (comercial, financeiro, controladoria, logística, suprimentos, corporativo, industrial, contabilidade) |
| Unidades de negócio (tenants) | 5 (`unit_01` … `unit_05`) |
| Fontes Bronze | 23 tabelas externas (Glue + Parquet) |
| Volume sintético / dia | ~550 k linhas / ~150 MB |
| Custo mensal AWS | ~$6 (vs. ~$800 na plataforma original) |
| Redução de custo | **~99%** |
| Tempo CI médio | < 5 min |
| `make up` → Airflow operacional | < 60 s |

---

## Quickstart

```bash
# Pré-requisito: Docker, Poetry, AWS CLI configurado, Terraform

# 1. Clone + dependências
git clone https://github.com/euvhmac/elt-pipeline-aws-medallion.git
cd elt-pipeline-aws-medallion
poetry install

# 2. Configurar ambiente
cp .env.example .env   # preencha com suas credenciais AWS

# 3. Provisionar infra AWS (única vez)
cd infra/envs/dev && terraform init && terraform apply && cd ../../..

# 4. Subir Airflow e gerar dados
make up     # http://localhost:8080  (airflow / airflow)
make seed   # gera 40 Parquets e faz upload para S3 Bronze

# 5. Rodar pipeline dbt
make dbt-build   # Silver → Gold → Platinum (45 modelos)
```

Guia completo de operação: [docs/RUNBOOK.md](docs/RUNBOOK.md).

---

## Arquitetura

```
┌──────────────────────────────────────────────────────────────────────┐
│                     LOCAL — Docker Compose                           │
│                                                                      │
│  Data Generator (Python + Faker + PyArrow)                          │
│  → gera 40 Parquets (8 datamarts × 5 tenants)                       │
│                                                                      │
│  Apache Airflow 2.9                                                  │
│  • dag_synthetic_source   → upload Bronze S3                        │
│  • dag_dbt_aws_detailed   → event-driven via Airflow Datasets        │
└────────────────────────────┬─────────────────────────────────────────┘
                             │ boto3 / dbt-athena
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         AWS — Serverless                             │
│                                                                      │
│   S3 (Parquet / Iceberg)    Glue Data Catalog    Athena v3 (Trino)  │
│                                                                      │
│   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌────────────────┐  │
│   │  Bronze  │ → │  Silver  │ → │   Gold   │ → │   Platinum     │  │
│   │  23 srcs │   │ 21 modls │   │ 18 modls │   │  6 modls       │  │
│   │  raw     │   │  clean   │   │  star    │   │  business      │  │
│   │ Parquet  │   │ Iceberg  │   │ Iceberg  │   │  Iceberg       │  │
│   └──────────┘   └──────────┘   └──────────┘   └────────────────┘  │
│                                                                      │
│   IAM  •  Secrets Manager  •  SNS → Lambda → Slack  •  CloudWatch   │
│   Terraform (S3 backend + DynamoDB lock)                             │
└──────────────────────────────────────────────────────────────────────┘
```

Diagrama detalhado e decisões: [docs/ARCHITECTURE_AWS.md](docs/ARCHITECTURE_AWS.md) · [docs/adr/](docs/adr/).

---

## Decisões de Design

| Decisão | Escolha | Alternativa Descartada | Razão Principal |
|---|---|---|---|
| Table format | Apache Iceberg | Delta Lake | Suporte nativo Athena v3 sem Spark |
| Compute SQL | Amazon Athena v3 | EMR Serverless | Pay-per-query, zero infra, ~99% custo menor |
| Orquestração | Airflow local (Docker) | MWAA | $0/mês vs ~$300/mês em dev |
| Multi-tenancy | Coluna `tenant_id` | Schema-per-tenant | Custo S3/Athena proporcional ao dado |
| Dados | Faker + PyArrow sintéticos | Dados reais | Zero NDA, 100% reproduzível |

Detalhes em [docs/adr/](docs/adr/).

---

## Stack Tecnológico

| Camada | Tecnologia |
|---|---|
| Storage | Amazon S3 + Apache Iceberg |
| Catálogo | AWS Glue Data Catalog |
| Engine SQL | Amazon Athena engine v3 (Trino) |
| Transformação | dbt-core 1.10 + dbt-athena-community |
| Orquestração | Apache Airflow 2.9 (Docker Compose) |
| Ingestão | Python 3.11 + Faker + PyArrow |
| IaC | Terraform 1.7+ (módulos reutilizáveis) |
| CI/CD | GitHub Actions (secrets-scan, dbt-ci, terraform-ci) |
| Qualidade | gitleaks, ruff, sqlfluff, dbt tests |
| Observabilidade | SNS + Lambda + CloudWatch + Slack |

Stack completa: [docs/TECHNOLOGIES.md](docs/TECHNOLOGIES.md).

---

## Estrutura do Repositório

```
elt-pipeline-aws-medallion/
├── dbt/                    # 45 modelos dbt (Silver / Gold / Platinum)
│   ├── models/
│   │   ├── silver/         # 21 modelos: limpeza e padronização multi-tenant
│   │   ├── gold/           # 18 modelos: star schema (9 dims + 7 facts + 2 DREs)
│   │   └── platinum/       # 6 modelos: visões de negócio por unidade
│   └── tests/              # singular tests (regras de negócio)
├── airflow/
│   ├── dags/               # dag_synthetic_source + dag_dbt_aws_detailed
│   └── docker-compose.yml
├── data-generator/         # gerador Python (Faker + PyArrow + PyArrow schemas)
├── infra/
│   ├── modules/            # s3-medallion, glue-catalog, iam-roles, sns-lambda
│   └── envs/dev/           # root module dev
├── .github/workflows/      # secrets-scan, dbt-ci, terraform-ci
├── docs/                   # documentação completa + 5 ADRs
├── Makefile                # atalhos: make up / seed / dbt-build / dbt-test
└── pyproject.toml          # dependências Python (Poetry)
```

---

## Modelo de Dados (Gold Layer — Star Schema)

```
                        ┌─────────────────┐
                        │  dim_calendrio  │
                        └────────┬────────┘
                                 │
  ┌──────────────┐               │              ┌──────────────────┐
  │ dim_clientes │               │              │   dim_produtos   │
  └──────┬───────┘               │              └────────┬─────────┘
         │          ┌────────────┴────────────┐          │
         └─────────►│       fct_vendas        │◄─────────┘
                    │  (grão: 1 item pedido)  │
                    └────────────┬────────────┘
                                 │
  ┌─────────────────┐            │              ┌──────────────────┐
  │  dim_empresas   │◄───────────┘              │  dim_vendedores  │
  └─────────────────┘                           └──────────────────┘
```

**Dimensions (9)**: `dim_calendrio`, `dim_clientes`, `dim_produtos`, `dim_vendedores`, `dim_fornecedores`, `dim_empresas`, `dim_funcionarios`, `dim_centros_custos`, `dim_plano_contas`

**Facts (7)**: `fct_vendas`, `fct_ordens_compra`, `fct_ordens_producao`, `fct_expedicao`, `fct_orcamento_projetos`, `fct_titulo_financeiro`, `fct_lancamentos`

**Analytics (2)**: `dre_contabil`, `dre_gerencial`

Documentação completa: [docs/DATA_MODEL.md](docs/DATA_MODEL.md) · [docs/MEDALLION_LAYERS.md](docs/MEDALLION_LAYERS.md).

---

## Documentação

| Documento | Conteúdo |
|---|---|
| [PROJECT_BLUEPRINT.md](docs/PROJECT_BLUEPRINT.md) | Pitch, métricas, stakeholders, roadmap estratégico |
| [ARCHITECTURE_AWS.md](docs/ARCHITECTURE_AWS.md) | Diagramas, fluxo de dados, componentes AWS |
| [DATA_MODEL.md](docs/DATA_MODEL.md) | Star schema Kimball, todas as tabelas |
| [MEDALLION_LAYERS.md](docs/MEDALLION_LAYERS.md) | Bronze → Silver → Gold → Platinum detalhado |
| [RUNBOOK.md](docs/RUNBOOK.md) | Setup, execução, troubleshooting operacional |
| [COST_ESTIMATE.md](docs/COST_ESTIMATE.md) | Breakdown de custo por serviço AWS |
| [CI_CD.md](docs/CI_CD.md) | Pipelines GitHub Actions, quality gates |
| [MIGRATION_FROM_AZURE.md](docs/MIGRATION_FROM_AZURE.md) | Mapeamento Azure Databricks → AWS |
| [TECHNOLOGIES.md](docs/TECHNOLOGIES.md) | Stack completo com versões |
| [INTERVIEW_NARRATIVE.md](docs/INTERVIEW_NARRATIVE.md) | Pitches de 5, 15 e 30 min para entrevistas |
| [SPRINT_ROADMAP.md](docs/SPRINT_ROADMAP.md) | 9 sprints com critérios de aceite |

**ADRs (Arquitetura Decision Records)**:
[ADR-0001 Iceberg vs Delta](docs/adr/0001-iceberg-vs-delta.md) · [ADR-0002 Athena vs EMR](docs/adr/0002-athena-vs-emr.md) · [ADR-0003 Airflow vs MWAA](docs/adr/0003-airflow-local-vs-mwaa.md) · [ADR-0004 Dados Sintéticos](docs/adr/0004-synthetic-data.md) · [ADR-0005 Monorepo](docs/adr/0005-monorepo-structure.md)

---

## Roadmap — Status das Sprints

| Sprint | Entrega | Status |
|---|---|---|
| 0 | Documentação inicial + sanitização | ✅ Concluído |
| 1 | Fundação local: Docker Compose, Airflow, data-generator | ✅ Concluído |
| 2 | Infra AWS: Terraform (S3, Glue, Athena, IAM, Secrets) | ✅ Concluído |
| 2.5 | Gerador histórico: sazonalidade, múltiplas datas | ✅ Concluído |
| 3 | Ingestão Bronze: DAG upload S3 + Glue partition projection | ✅ Concluído |
| 4 | dbt Silver + Gold datamart `comercial` (padrão base) | ✅ Concluído |
| 4.5 | dbt 7 datamarts restantes + DRE + Platinum (36 novos modelos) | ✅ Concluído |
| 5 | Orquestração Airflow event-driven (Datasets) + DAG dbt completa | ✅ Concluído |
| 6 | Observabilidade: SNS → Lambda → Slack + CloudWatch | ✅ Concluído |
| 7 | CI/CD: GitHub Actions (secrets-scan, dbt-ci, terraform-ci) | ✅ Concluído |
| 8 | Polimento de portfólio: README, docs, interview narrative | ✅ Concluído |

---

## Contribuindo

PRs são bem-vindos. Leia [CONTRIBUTING.md](CONTRIBUTING.md) para o processo de gitflow, conventional commits e checklist.

---

## Licença

MIT — veja [LICENSE](LICENSE).

---

## Autor

**Vhmac** · [@euvhmac](https://github.com/euvhmac)

Engenharia de Dados · Cloud-native analytics · Lakehouse Architecture

- Este projeto é uma **recriação para portfólio** de uma plataforma corporativa interna (acesso original sob NDA). Toda a lógica foi reimplementada com dados sintéticos.
- Tenants `unit_01..unit_05` são fictícios; nenhum dado real foi utilizado.
- Custo mensal validado em conta AWS Free Tier; veja [docs/COST_ESTIMATE.md](docs/COST_ESTIMATE.md).
