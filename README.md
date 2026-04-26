# ELT Pipeline AWS — Medallion Architecture

> Plataforma analítica multi-tenant em **AWS** com arquitetura **Medallion** (Bronze → Silver → Gold → Platinum), orquestrada por **Airflow**, transformações em **dbt-athena** sobre **Apache Iceberg**, infra como código em **Terraform**.

[![CI: secrets-scan](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/secrets-scan.yml/badge.svg)](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/secrets-scan.yml)
[![CI: dbt](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/dbt-ci.yml/badge.svg)](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/dbt-ci.yml)
[![CI: terraform](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/terraform-ci.yml/badge.svg)](https://github.com/euvhmac/elt-pipeline-aws-medallion/actions/workflows/terraform-ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![dbt](https://img.shields.io/badge/dbt-1.8+-orange)](https://www.getdbt.com/)
[![Airflow](https://img.shields.io/badge/Airflow-2.9-017CEE)](https://airflow.apache.org/)
[![Terraform](https://img.shields.io/badge/Terraform-1.7+-7B42BC)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-S3%20%7C%20Athena%20%7C%20Glue-FF9900)](https://aws.amazon.com/)
[![Release](https://img.shields.io/github/v/release/euvhmac/elt-pipeline-aws-medallion?label=release&color=blue)](https://github.com/euvhmac/elt-pipeline-aws-medallion/releases)

---

## TL;DR

Reconstrução em AWS de uma plataforma analítica multi-tenant originalmente em **Azure Databricks + Delta**. Mantém a lógica de negócio do datamart `comercial` (Silver + Gold star schema sobre Iceberg) com **redução de custo de ~99%** projetada (~$800/mês → ~$6/mês).

**Estado atual**: pipeline E2E funcional (sintético → S3/Iceberg → dbt-athena → Slack alerts) com CI/CD verde. Datamart `comercial` completo; demais 7 datamarts no backlog (Sprint 4.5).

---

## Quickstart

```bash
# 1. Clone
git clone https://github.com/euvhmac/elt-pipeline-aws-medallion.git
cd elt-pipeline-aws-medallion

# 2. Configurar
cp .env.example .env
# Edite .env com suas credenciais AWS

# 3. Subir e executar
make up           # sobe Airflow + Postgres
make seed         # gera dados sintéticos + upload S3
make dbt-build    # roda 55 modelos dbt
```

UI Airflow: http://localhost:8080 (`airflow`/`airflow`)

Detalhes em [docs/RUNBOOK.md](docs/RUNBOOK.md).

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│            Local: Airflow (Docker Compose)                  │
│                                                             │
│   dag_synthetic_source ──► [Airflow Datasets] ──►           │
│                                          dag_dbt_aws_detailed│
└─────────────┬─────────────────────────────────────┬─────────┘
              │                                     │
              ▼                                     ▼
       ┌─────────────┐                      ┌──────────────┐
       │ Data Generator│                    │ dbt-athena   │
       │ (Python+Faker)│                    │ (~55 models) │
       └──────┬───────┘                     └──────┬───────┘
              │                                    │
              │   AWS Cloud                        │
              ▼                                    ▼
       ┌─────────────────────────────────────────────────┐
       │  S3 (Iceberg) + Glue Catalog + Athena (Trino)   │
       │                                                 │
       │   Bronze ──► Silver ──► Gold ──► Platinum       │
       │   (raw)     (clean)   (star)   (business)       │
       └─────────────────┬───────────────────────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │ SNS → Lambda │
                  │  → Slack     │
                  └──────────────┘
```

Detalhes em [docs/ARCHITECTURE_AWS.md](docs/ARCHITECTURE_AWS.md).

---

## Métricas do Projeto

| Item | Valor |
|---|---|
| Modelos dbt (target final) | 55 (30 Silver + 16 Gold + 9 Platinum) |
| Modelos dbt (entregues) | 11 (5 Silver + 5 Gold + 1 teste singular) — datamart `comercial` |
| Datamarts simulados (target) | 8 (comercial, financeiro, controladoria, logística, suprimentos, corporativo, industrial, contabilidade) |
| Datamarts entregues | 1 (comercial) — padrão replicável para os 7 restantes |
| Unidades de negócio | 5 (`unit_01`..`unit_05`) |
| Tabelas Bronze | 40 (8 × 5 tenants) |
| Volume sintético/dia | ~550k linhas / ~150 MB |
| Custo mensal AWS estimado | ~$5-7 |
| CI workflows | 5 (compose-validate, data-generator-tests, dbt-ci, terraform-ci, secrets-scan) |
| Pull Shark count 🦈 | 11 PRs mergeados |

---

## Stack

- **Storage**: Amazon S3 + Apache Iceberg
- **Engine SQL**: Amazon Athena (engine v3 / Trino)
- **Catálogo**: AWS Glue Data Catalog
- **Transformação**: dbt-athena
- **Orquestração**: Apache Airflow 2.9 (Docker Compose local)
- **Ingestão**: Gerador Python sintético (Faker + PyArrow)
- **IaC**: Terraform 1.7+
- **CI/CD**: GitHub Actions
- **Observabilidade**: SNS + Lambda + CloudWatch

Stack completa em [docs/TECHNOLOGIES.md](docs/TECHNOLOGIES.md).

---

## Documentação

A documentação completa está em [`docs/`](docs/):

### Visão geral
- [Blueprint do Projeto](docs/PROJECT_BLUEPRINT.md) — pitch, métricas, stakeholders
- [Arquitetura AWS](docs/ARCHITECTURE_AWS.md) — diagramas e fluxos
- [Migração de Azure](docs/MIGRATION_FROM_AZURE.md) — mapeamento componente-a-componente
- [Roadmap de Sprints](docs/SPRINT_ROADMAP.md) — 8 sprints com critérios QA + Tech Lead

### Técnico
- [Stack Tecnológico](docs/TECHNOLOGIES.md)
- [Modelo de Dados](docs/DATA_MODEL.md) — star schema multi-tenant
- [Camadas Medallion](docs/MEDALLION_LAYERS.md) — Bronze/Silver/Gold/Platinum
- [Gerador Sintético](docs/SOURCE_DATA_GENERATOR.md)
- [CI/CD](docs/CI_CD.md)
- [Runbook](docs/RUNBOOK.md) — operação e troubleshooting
- [Estimativa de Custos](docs/COST_ESTIMATE.md)

### Apresentação
- [Narrativa de Entrevista](docs/INTERVIEW_NARRATIVE.md) — pitches 5/15/30 min

### Decisões Arquiteturais (ADRs)
- [ADR-0001 — Iceberg vs Delta](docs/adr/0001-iceberg-vs-delta.md)
- [ADR-0002 — Athena vs EMR](docs/adr/0002-athena-vs-emr.md)
- [ADR-0003 — Airflow Local vs MWAA](docs/adr/0003-airflow-local-vs-mwaa.md)
- [ADR-0004 — Dados Sintéticos](docs/adr/0004-synthetic-data.md)
- [ADR-0005 — Estrutura Monorepo](docs/adr/0005-monorepo-structure.md)

---

## Estrutura do Repositório

```
elt-pipeline-aws-medallion/
├── docs/             # Documentação central + ADRs
├── dbt/              # Modelos dbt (Silver/Gold/Platinum)
├── airflow/          # DAGs + docker-compose
├── data-generator/   # Gerador Python (Faker + PyArrow)
├── infra/            # Terraform (modules + envs)
├── .github/workflows/# CI/CD
├── Makefile          # Atalhos UX
└── README.md
```

---

## Roadmap

| Sprint | Foco | Status |
|---|---|---|
| 0 | Documentação inicial + ADRs | ✅ |
| 1 | Fundação local (Docker Compose) | ✅ |
| 2 | Infra AWS (Terraform) | ✅ |
| 2.5 | Bootstrap state remoto | ✅ |
| 3 | Ingestão Bronze (S3 + Glue) | ✅ |
| 4 | Transformação dbt (Silver+Gold `comercial`) | ✅ |
| 5 | Airflow orquestrando dbt | ✅ |
| 6 | Observabilidade (SNS+Lambda+Slack) | ✅ |
| 7 | CI/CD & Quality Gates | ✅ |
| 8 | Polimento de portfólio | ✅ |
| 4.5 | Replicar dbt para 7 datamarts restantes | ⬜ backlog |

Detalhes em [docs/SPRINT_ROADMAP.md](docs/SPRINT_ROADMAP.md). Releases em [Releases](https://github.com/euvhmac/elt-pipeline-aws-medallion/releases) (CalVer `YYYY.MM.PATCH`).

---

## Contribuindo

PRs são bem-vindos. Veja [CONTRIBUTING.md](CONTRIBUTING.md) para o processo.

---

## Licença

MIT — veja [LICENSE](LICENSE).

---

## Autor

**Vhmac** — [@euvhmac](https://github.com/euvhmac)

Engenharia de Dados | Cloud-native analytics | Lakehouse Architecture

---

## Notas

- Este projeto é uma **recriação para portfólio** de uma plataforma corporativa interna (acesso original sob NDA). Toda a lógica foi reimplementada com dados sintéticos.
- Tenants `unit_01..unit_05` são fictícios; nenhum dado real foi utilizado.
- Custo mensal validado em conta AWS Free Tier; veja [docs/COST_ESTIMATE.md](docs/COST_ESTIMATE.md).
