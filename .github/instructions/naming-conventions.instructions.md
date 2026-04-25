---
applyTo: '**'
---

# Naming Conventions — Single Source of Truth

> Convenções de nomenclatura para todos os artefatos do repositório. Outras instructions referenciam este arquivo.

---

## Tabelas dbt

### Por camada

| Camada | Padrão | Exemplo |
|---|---|---|
| Bronze | `<datamart>.<entidade>` (Glue catalog) | `comercial.vendas` |
| Silver | `silver_dw_<entidade>` | `silver_dw_clientes` |
| Gold dimensions | `dim_<entidade>` (singular) | `dim_clientes` |
| Gold facts | `fct_<evento>` (singular) | `fct_vendas` |
| Gold DRE | `dre_<contexto>` | `dre_contabil`, `dre_gerencial` |
| Platinum | `<modelo>_unit_NN` ou `<conceito>` | `dre_contabil_unit_01`, `controle_inadimplentes` |

### Regras
- **snake_case** sempre
- **Singular** para dims/facts (`dim_cliente`, não `dim_clientes` — ✅ exceção histórica deste projeto: usamos plural por convenção do baseline)
- **Sem prefixo de schema** no nome do arquivo `.sql`
- Nome do arquivo `.sql` = nome do modelo (`fct_vendas.sql` → `fct_vendas`)

---

## Colunas

### Sufixos padrão

| Sufixo | Tipo de coluna | Exemplo |
|---|---|---|
| `_id` | Natural key (vem do source) | `cliente_id`, `venda_id` |
| `_sk` | Surrogate key (gerada via `dbt_utils`) | `cliente_sk`, `venda_sk` |
| `_at` | Timestamp | `created_at`, `updated_at` |
| `_id` (em facts) | FK para dim | `cliente_sk` é o usual; `data_id` para `dim_calendrio` |

### Prefixos padrão

| Prefixo | Conceito | Tipo | Exemplo |
|---|---|---|---|
| `dt_` | Data/Date | `DATE` ou `TIMESTAMP` | `dt_venda`, `dt_emissao` |
| `vlr_` | Valor monetário | `DECIMAL(18,2)` | `vlr_total`, `vlr_unitario` |
| `qtd_` | Quantidade | `DECIMAL(18,4)` ou `INTEGER` | `qtd_vendida` |
| `pct_` | Percentual | `DECIMAL(5,2)` | `pct_desconto` |
| `nm_` | Nome (opcional) | `VARCHAR` | `nm_cliente` (ou `nome_cliente`) |
| `cd_` | Código (opcional) | `VARCHAR` | `cd_produto` (ou `codigo_produto`) |
| `dsc_` | Descrição (opcional) | `VARCHAR` | `dsc_status` (ou `descricao_status`) |

### Colunas obrigatórias

| Coluna | Camada | Tipo | Função |
|---|---|---|---|
| `tenant_id` | Silver+ | `VARCHAR` | Identificador da unidade de negócio |
| `_dbt_loaded_at` | Silver+ | `TIMESTAMP` | Audit column injetada pelo dbt |
| `_dbt_source_relation` | Quando UNION de sources | `VARCHAR` | Origem do registro (Iceberg) |

### Anti-patterns
- ❌ Nomes em maiúsculas: `CLIENTE_ID`
- ❌ camelCase: `clienteId`
- ❌ Abreviações obscuras: `cli_dt_dt`
- ❌ Singular vs plural inconsistente entre tabelas relacionadas
- ❌ `id` puro sem prefixo de entidade

---

## AWS Resources

### Padrão geral

```
<project>-<component>-<env>
```

- `project`: `elt-pipeline`
- `component`: descritivo do recurso
- `env`: `dev` | `prd`

### Exemplos por serviço

| Serviço | Padrão | Exemplo |
|---|---|---|
| S3 buckets | `elt-pipeline-<layer>-<env>` | `elt-pipeline-bronze-dev` |
| S3 athena results | `elt-pipeline-athena-results-<env>` | `elt-pipeline-athena-results-dev` |
| S3 dbt artifacts | `elt-pipeline-dbt-artifacts-<env>` | `elt-pipeline-dbt-artifacts-prd` |
| Glue databases | `<layer>` (sem prefixo, dentro do catalog) | `bronze`, `silver`, `gold` |
| IAM roles | `<project>-<role>-<env>` | `elt-pipeline-dbt-athena-role-dev` |
| Lambda functions | `<project>-<function>-<env>` | `elt-pipeline-slack-notifier-dev` |
| SNS topics | `<project>-<topic>-<env>` | `elt-pipeline-alerts-dev` |
| Secrets Manager | `<project>/<secret-name>` | `elt-pipeline/slack-webhook` |
| Athena workgroup | `<project>-<env>` | `elt-pipeline-dev` |
| DynamoDB (tf lock) | `<project>-tfstate-lock` | `elt-pipeline-tfstate-lock` |

### Regras
- **kebab-case** (lowercase com hífens)
- **Sem underscores** em recursos AWS (compatibilidade DNS S3)
- **Sufixo `<env>` sempre** para isolamento
- **Sem caracteres especiais** exceto `-` e `/` (Secrets Manager)

### Tags obrigatórias (Terraform `default_tags`)

```hcl
default_tags {
  tags = {
    Project     = "elt-pipeline-aws-medallion"
    Environment = var.env
    ManagedBy   = "Terraform"
    Owner       = "vhmac"
    Component   = "<component>"  # opcional, override no recurso
  }
}
```

---

## Airflow

### DAGs
- **Padrão**: `dag_<dominio>_<acao>`
- **Exemplos**:
  - `dag_synthetic_source` — gera dados sintéticos
  - `dag_dbt_aws_detailed` — executa dbt completo
  - `dag_dbt_aws_silver_only` — executa apenas Silver (futuro)
- **DAG ID** = nome do arquivo sem `.py`

### Tasks
- **Padrão**: `<verb>_<noun>` em snake_case
- **Verbs comuns**: `generate`, `upload`, `register`, `validate`, `build`, `test`, `notify`
- **Exemplos**:
  - `generate_data`
  - `upload_to_s3`
  - `register_partitions`
  - `build_silver_clientes`
  - `test_gold_models`

### TaskGroups
- **Padrão**: `<layer>_layer` ou `<phase>_phase`
- **Exemplos**: `silver_layer`, `gold_layer`, `platinum_layer`, `tests_layer`

### Datasets
- **Padrão**: URI `s3://<bucket>/<path>` (Airflow 2.4+ Dataset)
- **Exemplo**: `Dataset("s3://elt-pipeline-bronze-dev/comercial/")`

---

## Terraform

### Modules
- **Padrão**: `<componente>` ou `<componente>-<sub>` em kebab-case
- **Localização**: `infra/modules/<nome>/`
- **Exemplos**: `s3-medallion`, `glue-catalog`, `iam-roles`, `secrets-manager`, `sns-lambda`

### Files dentro de module
- `main.tf` — recursos principais
- `variables.tf` — inputs
- `outputs.tf` — outputs (com `description`)
- `versions.tf` — provider/terraform version pinning
- `README.md` — uso, inputs, outputs, exemplos

### Variables
- **Padrão**: `snake_case`
- **Sufixos comuns**:
  - `_arn` (ARN AWS)
  - `_name` (nome de recurso)
  - `_id` (ID AWS)
  - `_enabled` (boolean feature flag)

### Workspaces / Envs
- `infra/envs/dev/`
- `infra/envs/prd/`
- Nunca usar `default` workspace em produção

---

## Python

### Files
- **snake_case**: `data_generator.py`, `slack_notifier.py`
- **Test files**: `test_<module>.py` em `tests/`
- **Schemas**: `<datamart>.py` (ex: `schemas/comercial.py`)

### Modules / Packages
- **snake_case**: `data_generator/`, `airflow/dags/utils/`

### Functions
- **snake_case**: `generate_venda()`, `upload_to_s3()`
- **Verbs em inglês** para ações
- **Booleanos**: prefixo `is_`, `has_`, `should_`

### Classes
- **PascalCase**: `VendaGenerator`, `SchemaValidator`

### Constants
- **UPPER_SNAKE_CASE**: `DEFAULT_VOLUME`, `MAX_RETRIES`

### Variables
- **snake_case**, descritivas: `total_vendas` em vez de `tv`

---

## Git

### Branches

| Tipo | Padrão | Exemplo |
|---|---|---|
| Feature | `feat/<scope>-<short-desc>` | `feat/dbt-fct-devolucao` |
| Fix | `fix/<scope>-<bug>` | `fix/airflow-callback-retry` |
| Docs | `docs/<scope>` | `docs/adr-openlineage` |
| Refactor | `refactor/<scope>` | `refactor/airflow-utils-extract` |
| Chore | `chore/<scope>` | `chore/deps-update` |

### Tags (Releases)

**CalVer**: `YYYY.MM.PATCH`

- `2025.04.0` — primeira release Sprint 0
- `2025.05.0` — Sprint 1 completa
- `2025.06.1` — Hotfix Sprint 5

### Commits

Ver [commits-prs.instructions.md](commits-prs.instructions.md).

---

## SQL Files

- **snake_case** = nome do modelo dbt
- Mesmo nome do model: `fct_vendas.sql` → modelo `fct_vendas`
- Headers obrigatórios em facts:

```sql
-- Modelo: fct_vendas
-- Grão: 1 linha = 1 item de pedido (split de venda)
-- Granularidade: tenant_id × venda_id
-- Refresh: incremental merge, lookback 1 dia
```

---

## Pasta / Diretório

- **Sempre kebab-case** para diretórios públicos: `data-generator/`
- **snake_case** para módulos Python importáveis: `data_generator/src/`
- Inconsistência aceita: `airflow/dags/utils/` (Python convention)

---

## Documentação

### Arquivos `.md`

- **UPPER_SNAKE_CASE** para docs principais: `RUNBOOK.md`, `COST_ESTIMATE.md`
- **kebab-case** para ADRs: `0001-iceberg-vs-delta.md`
- **Lowercase** para arquivos especiais: `README.md`, `CHANGELOG.md`, `LICENSE`

### Headers internos
- H1 único por documento (título)
- H2 para seções principais
- H3+ para subseções
- TOC manual em docs > 200 linhas

---

## Resumo Visual

```
elt-pipeline-aws-medallion/        ← kebab-case (pasta)
├── dbt/
│   └── models/gold/
│       ├── dim_clientes.sql       ← snake_case (sql + dbt model)
│       └── fct_vendas.sql
├── airflow/dags/
│   ├── dag_synthetic_source.py    ← snake_case (DAG file)
│   └── utils/
│       └── callbacks.py
├── data-generator/                ← kebab-case (pasta pública)
│   └── src/
│       └── data_generator/        ← snake_case (Python package)
│           └── schemas/
│               └── comercial.py
├── infra/
│   ├── modules/
│   │   └── s3-medallion/          ← kebab-case (TF module)
│   └── envs/dev/
└── docs/
    ├── RUNBOOK.md                 ← UPPER_SNAKE_CASE
    └── adr/
        └── 0001-iceberg-vs-delta.md  ← kebab-case
```

---

## Validação

CI deve validar (Sprint 7):
- `sqlfluff` valida snake_case em SQL
- `ruff` valida PEP8 em Python
- `tflint` valida naming AWS em Terraform
- Pre-commit hook bloqueia camelCase em SQL/Python
