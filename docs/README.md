# Documentação — ELT Pipeline AWS Medallion

> **Plataforma de dados Lakehouse multi-tenant na AWS**, baseada em arquitetura Medallion (Bronze → Silver → Gold → Platinum), orquestrada com Apache Airflow, transformada com dbt e armazenada em Apache Iceberg sobre S3 + Athena.

Esta documentação cobre o projeto de portfólio que **migra** uma plataforma DW corporativa originalmente construída em Azure (Databricks + AKS + Airbyte) para uma arquitetura equivalente na AWS, preservando os padrões arquiteturais e adaptando para um stack open-source mais econômico e moderno.

---

## Índice da Documentação

### Visão e Estratégia
| Documento | Conteúdo |
|---|---|
| [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md) | Visão executiva: o que é, por que, para quem |
| [MIGRATION_FROM_AZURE.md](MIGRATION_FROM_AZURE.md) | Mapeamento componente-a-componente Azure → AWS |
| [INTERVIEW_NARRATIVE.md](INTERVIEW_NARRATIVE.md) | Scripts de apresentação para entrevistas (5/15/30 min) |

### Arquitetura
| Documento | Conteúdo |
|---|---|
| [ARCHITECTURE_AWS.md](ARCHITECTURE_AWS.md) | Arquitetura AWS completa com 4 diagramas |
| [TECHNOLOGIES.md](TECHNOLOGIES.md) | Stack tecnológico — papel de cada componente |
| [DATA_MODEL.md](DATA_MODEL.md) | Star schema, fatos, dimensões e DRE multi-tenant |
| [MEDALLION_LAYERS.md](MEDALLION_LAYERS.md) | Camadas Bronze/Silver/Gold/Platinum detalhadas |
| [SOURCE_DATA_GENERATOR.md](SOURCE_DATA_GENERATOR.md) | Design do gerador de dados sintéticos |

### Execução e Operação
| Documento | Conteúdo |
|---|---|
| [SPRINT_ROADMAP.md](SPRINT_ROADMAP.md) | Roadmap de 8 sprints com critérios QA + Tech Lead |
| [RUNBOOK.md](RUNBOOK.md) | Como rodar localmente + deploy AWS |
| [CI_CD.md](CI_CD.md) | Workflows GitHub Actions e quality gates |
| [COST_ESTIMATE.md](COST_ESTIMATE.md) | Estimativa de custos AWS (free tier) |

### Architecture Decision Records (ADRs)
| Documento | Conteúdo |
|---|---|
| [adr/0001-iceberg-vs-delta.md](adr/0001-iceberg-vs-delta.md) | Por que Apache Iceberg em vez de Delta Lake |
| [adr/0002-athena-vs-emr.md](adr/0002-athena-vs-emr.md) | Por que Athena em vez de EMR Serverless |
| [adr/0003-airflow-local-vs-mwaa.md](adr/0003-airflow-local-vs-mwaa.md) | Por que Airflow Docker local em vez de MWAA |
| [adr/0004-synthetic-data.md](adr/0004-synthetic-data.md) | Por que gerador Python em vez de dataset público |
| [adr/0005-monorepo-structure.md](adr/0005-monorepo-structure.md) | Por que monorepo unificando dbt + airflow + infra |

---

## Como Navegar

**Recrutador / Tech Lead avaliando o portfólio**:
1. [README do repo (root)](../README.md) — pitch e quickstart
2. [PROJECT_BLUEPRINT.md](PROJECT_BLUEPRINT.md) — visão executiva
3. [ARCHITECTURE_AWS.md](ARCHITECTURE_AWS.md) — arquitetura visual
4. [INTERVIEW_NARRATIVE.md](INTERVIEW_NARRATIVE.md) — narrativa pronta

**Engenheiro técnico explorando**:
1. [TECHNOLOGIES.md](TECHNOLOGIES.md) — stack
2. [MEDALLION_LAYERS.md](MEDALLION_LAYERS.md) — modelos
3. [adr/](adr/) — decisões técnicas justificadas
4. [RUNBOOK.md](RUNBOOK.md) — rodar localmente

**Executando o projeto**:
1. [RUNBOOK.md](RUNBOOK.md) — passo a passo
2. [CI_CD.md](CI_CD.md) — automação
3. [COST_ESTIMATE.md](COST_ESTIMATE.md) — controle de custos

---

## Referências Externas

Este projeto é uma **migração** baseada em uma plataforma corporativa privada. Os repositórios-fonte (sob NDA) são:

- `prj-bigdata-pipeline` — projeto dbt original (Azure Databricks)
- `prj-bigdata-pipeline-airflow` — DAGs Airflow originais (AKS)

Esses repositórios servem como **baseline arquitetural** e não são modificados durante a migração. Veja [MIGRATION_FROM_AZURE.md](MIGRATION_FROM_AZURE.md) para o mapeamento completo.
