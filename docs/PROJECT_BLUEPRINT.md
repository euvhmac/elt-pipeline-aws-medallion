# Project Blueprint — ELT Pipeline AWS Medallion

## Pitch em 30 segundos

Plataforma de dados Lakehouse multi-tenant na AWS que ingere dados sintéticos de 5 unidades de negócio através de uma pipeline ELT batch, transforma-os em camadas analíticas progressivas (Bronze → Silver → Gold → Platinum) e disponibiliza modelos analíticos prontos para consumo de BI. Toda a infraestrutura é gerenciada por Terraform, orquestrada por Apache Airflow e validada por CI/CD com GitHub Actions.

## Origem do Projeto

Este projeto é uma **migração arquitetural** de uma plataforma DW corporativa real, originalmente construída em Azure (Databricks + AKS + Airflow + Airbyte). A migração reproduz fielmente os padrões e responsabilidades de cada camada, adaptando-os para um stack AWS moderno e econômico:

- **Origem (referência interna sob NDA)**:
  - Azure Databricks SQL Warehouse + Delta Tables
  - AKS (Airflow + Airbyte via Helm)
  - Unity Catalog para governança
  - Multi-tenant: 7 empresas / 8 data marts
- **Destino (este projeto público)**:
  - S3 + Apache Iceberg + Athena
  - Apache Airflow em Docker Compose local
  - AWS Glue Data Catalog para governança
  - Multi-tenant: 5 unidades anonimizadas / 8 data marts

## Por que este projeto existe

### Para quem busca emprego (autor do projeto)

- **Demonstração de skills sêniores**: arquitetura Lakehouse, IaC, CI/CD, orquestração event-driven, modelagem dimensional, qualidade de dados
- **Defensabilidade em entrevistas**: cada decisão técnica tem ADR justificando trade-offs
- **Replicabilidade**: qualquer recrutador consegue rodar localmente em < 10 minutos
- **Custo controlado**: cabe no AWS Free Tier ($200 créditos)

### Para quem avalia (recrutador / tech lead)

- **Código que roda**: não é "tutorial demo" — é pipeline funcional end-to-end
- **Padrões reais**: Airflow Datasets, dbt incremental merge, Iceberg, materialização por camada
- **Engenharia de plataforma**: Terraform modular, GitHub Actions com quality gates, observabilidade
- **Documentação madura**: ADRs, runbook, narrativa de entrevista, estimativa de custos

## Problema de negócio simulado

A plataforma simula uma operação real: **um grupo de 5 unidades de negócio com ERPs isolados**, sem comunicação entre si. O pipeline resolve:

- Consolidação de DRE Contábil e Gerencial por unidade e do grupo
- Controle de inadimplentes em tempo real
- Análise de vendas e faturamento com dimensões enriquecidas
- Visões analíticas (Platinum) prontas para consumo BI

## Métricas do Projeto

| Métrica | Valor |
|---|---|
| Modelos dbt | 55 (30 Silver + 16 Gold + 9 Platinum) |
| Tabelas Bronze | 40 (5 tenants × 8 datamarts) |
| Tasks Airflow | ~70 (granularidade por modelo) |
| Módulos Terraform | 4 (s3-medallion, glue-catalog, iam-roles, secrets-manager) |
| Workflows CI/CD | 3 (dbt-ci, terraform-ci, secrets-scan) |
| ADRs | 5+ |
| Custo mensal estimado | $5–15 |

## Diferencial de Portfólio

Projetos comuns de portfólio em DE costumam ser:
- ❌ Tutorial replicado (Olist + Postgres + Metabase)
- ❌ Stack inflada sem justificativa (10 ferramentas para um job que faz `SELECT *`)
- ❌ Sem testes, sem CI, sem IaC
- ❌ Documentação só no README

Este projeto é diferente:
- ✅ **Migração arquitetural defensável** com ADRs justificando cada escolha
- ✅ **Stack mínima e moderna** (S3 + Iceberg + Athena + Airflow + dbt)
- ✅ **Engenharia de plataforma completa** (Terraform + CI/CD + observabilidade)
- ✅ **Documentação para entrevista** (script 5/15/30 min)
- ✅ **Reproduzível**: clone + `make all` = pipeline rodando

## O que NÃO está incluído (escopo definido)

Decisões deliberadas para manter foco:

- ❌ MWAA (Airflow gerenciado) — caro, fica como ADR explicando trade-off
- ❌ Streaming/CDC (Kinesis, MSK, DMS) — projeto é batch
- ❌ QuickSight ou ferramenta BI real — `dbt docs` já cumpre função demo
- ❌ Lake Formation row-level security — overkill para portfólio
- ❌ Multi-region/DR — não cabe no free tier

Esses pontos são abordados em ADRs com justificativa técnica.

## Public-friendly: zero secrets, zero referências reais

Este repositório é público. Nada do projeto-fonte original (nomes de empresas, hosts Databricks, tokens, connection IDs Airbyte) está exposto. A migração foi precedida por uma sanitização auditada (gitleaks + grep zero-tolerance), e os 5 tenants são identificados apenas como `unit_01..unit_05`.

## Próximos Passos

Veja [SPRINT_ROADMAP.md](SPRINT_ROADMAP.md) para o plano de execução em 8 sprints e [RUNBOOK.md](RUNBOOK.md) para começar a rodar localmente.
