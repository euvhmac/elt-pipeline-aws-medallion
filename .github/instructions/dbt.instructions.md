---
applyTo: 'dbt/**/*.{sql,yml}'
---

# dbt Instructions

> Padrões de modelos, configs, testes e macros para dbt-athena + Iceberg.

---

## Stack dbt

- **dbt-core**: 1.7+
- **dbt-athena-community**: 1.7+
- **Engine**: Athena v3 (Trino)
- **Format**: Apache Iceberg (todas as tabelas Silver+)
- **Catalog**: AWS Glue
- **Storage**: S3

---

## Estrutura de Camadas

```
dbt/models/
├── bronze/         ← sources only (não materializa, registra metadata)
├── silver/         ← incremental + merge, limpeza/padronização
├── gold/           ← star schema (dims + facts + DREs)
└── platinum/       ← views por unidade de negócio
```

---

## Materialização por Camada

| Camada | Materialization | Strategy | Justificativa |
|---|---|---|---|
| Bronze | source (não dbt) | — | Registrado via Glue/CTAS externo |
| Silver | `incremental` | `merge` | Volume alto, refresh frequente |
| Gold dims | `incremental` | `merge` (SCD1) ou `delete+insert` | Mudanças de atributos |
| Gold facts | `incremental` | `merge` | Volume + reprocessamento idempotente |
| Gold DRE | `table` | — | Cálculo pesado, refresh diário |
| Platinum | `view` (default) | — | Lógica leve, reflete Gold |

### Override quando necessário (`{{ config(...) }}` no topo do `.sql`):

```sql
{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['tenant_id', 'venda_id'],
    table_type='iceberg',
    format='parquet',
    on_schema_change='append_new_columns',
    partitioned_by=['tenant_id', 'month(dt_venda)']
  )
}}
```

---

## Config Iceberg Padrão

**Sempre incluir** em models Silver/Gold incrementais:

```sql
{{
  config(
    table_type='iceberg',
    format='parquet',
    on_schema_change='append_new_columns',
    incremental_strategy='merge'
  )
}}
```

### Por que esses defaults?
- `table_type='iceberg'`: ACID, time travel, schema evolution
- `format='parquet'`: colunar, comprimido, otimizado p/ Athena
- `on_schema_change='append_new_columns'`: tolerante a evolução schema
- `incremental_strategy='merge'`: idempotente em re-runs

---

## Unique Keys (Composite)

**Sempre composite com `tenant_id`** em modelos multi-tenant:

```sql
unique_key=['tenant_id', 'venda_id']
```

### Por quê?
- Evita colisão entre tenants
- Aproveita partition pruning no merge
- Garante idempotência por tenant

### Anti-pattern
```sql
-- ❌ ERRADO: pode colidir entre tenants
unique_key='venda_id'
```

---

## Surrogate Keys

**Sempre via `dbt_utils.generate_surrogate_key`** em dims/facts Gold:

```sql
SELECT
  {{ dbt_utils.generate_surrogate_key(['tenant_id', 'cliente_id']) }} AS cliente_sk,
  tenant_id,
  cliente_id,
  ...
```

### Regras
- SK = MD5 hash de `[tenant_id, natural_key]`
- Sufixo `_sk` no nome
- Imutável (nunca recalcular para o mesmo NK)
- Hash determinístico via `dbt_utils`

---

## Audit Columns

**Toda tabela Silver/Gold tem**:

```sql
SELECT
  ...
  CURRENT_TIMESTAMP AS _dbt_loaded_at
```

Ou via post-hook:

```sql
{{
  config(
    post_hook="ALTER TABLE {{ this }} ..."
  )
}}
```

---

## Source Freshness

**Obrigatório em `sources.yml`**:

```yaml
sources:
  - name: bronze
    tables:
      - name: vendas
        loaded_at_field: _dbt_loaded_at
        freshness:
          warn_after: { count: 24, period: hour }
          error_after: { count: 48, period: hour }
```

CI bloqueia se source freshness falha (Sprint 7).

---

## Lookback Window

Em modelos incrementais com timestamps, usar lookback para capturar updates atrasados:

```sql
{% if is_incremental() %}
  WHERE dt_venda >= (
    SELECT COALESCE(MAX(dt_venda), DATE '1900-01-01') - INTERVAL '1' DAY
    FROM {{ this }}
  )
{% endif %}
```

**Default**: 1 dia. Ajustar caso a caso.

---

## Refs e Sources

### ✅ Sempre

```sql
FROM {{ ref('silver_dw_vendas') }}
JOIN {{ ref('dim_clientes') }} ON ...

FROM {{ source('bronze', 'vendas') }}
```

### ❌ Nunca

```sql
FROM bronze.vendas              -- hardcoded schema
FROM "silver"."dw_vendas"        -- hardcoded
FROM gold_dev.dim_clientes      -- ambiente específico
```

---

## Estrutura de Modelo Padrão

```sql
-- Modelo: fct_vendas
-- Grão: 1 linha = 1 item de pedido
-- Granularidade: tenant_id × venda_id × produto_id

{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['tenant_id', 'venda_id', 'produto_id'],
    table_type='iceberg',
    format='parquet',
    on_schema_change='append_new_columns',
    partitioned_by=['tenant_id', 'month(dt_venda)']
  )
}}

WITH source AS (
  SELECT *
  FROM {{ ref('silver_dw_vendas') }}
  {% if is_incremental() %}
    WHERE dt_venda >= (SELECT COALESCE(MAX(dt_venda), DATE '1900-01-01') - INTERVAL '1' DAY FROM {{ this }})
  {% endif %}
),

dim_cliente AS (
  SELECT cliente_sk, tenant_id, cliente_id
  FROM {{ ref('dim_clientes') }}
),

joined AS (
  SELECT
    {{ dbt_utils.generate_surrogate_key(['s.tenant_id', 's.venda_id', 's.produto_id']) }} AS venda_sk,
    s.tenant_id,
    s.venda_id,
    s.produto_id,
    c.cliente_sk,
    s.dt_venda,
    s.qtd_vendida,
    s.vlr_unitario,
    s.vlr_total,
    CURRENT_TIMESTAMP AS _dbt_loaded_at
  FROM source s
  LEFT JOIN dim_cliente c
    ON s.tenant_id = c.tenant_id
    AND s.cliente_id = c.cliente_id
)

SELECT * FROM joined
```

---

## Macros Reutilizáveis

Localização: `dbt/macros/`. Convenções:

- **Prefixo `clean_`** para limpeza: `clean_and_cast`, `clean_string`
- **Prefixo `get_`** para resolução: `get_custom_schema`
- **Prefixo `test_`** para testes singulares: `test_no_overlap_periods`
- Documentar parâmetros em comentário no topo do macro

---

## Schema YML

**Toda pasta tem `schema.yml`** documentando:
- Description em PT-BR
- Columns críticas (PK, FK, business)
- Tests por coluna
- Owner em meta tag

Exemplo mínimo Gold:

```yaml
version: 2

models:
  - name: fct_vendas
    description: "Tabela fato de vendas com 1 linha por item de pedido."
    config:
      meta:
        owner: vhmac
        layer: gold
    columns:
      - name: venda_sk
        description: "Surrogate key composta de [tenant_id, venda_id, produto_id]"
        tests:
          - not_null
          - unique
      - name: tenant_id
        description: "Identificador da unidade de negócio"
        tests:
          - not_null
          - accepted_values:
              values: ['unit_01', 'unit_02', 'unit_03', 'unit_04', 'unit_05']
      - name: cliente_sk
        description: "FK para dim_clientes"
        tests:
          - not_null
          - relationships:
              to: ref('dim_clientes')
              field: cliente_sk
      - name: dt_venda
        description: "Data da venda"
        tests:
          - not_null
      - name: vlr_total
        description: "Valor total do item (DECIMAL(18,2))"
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: ">= 0"
```

---

## Anti-Patterns dbt

- ❌ `SELECT *` em Gold/Platinum (sempre listar colunas explícitas)
- ❌ Hardcoded schemas (`FROM gold.dim_x`)
- ❌ Modelos sem `unique_key` em incremental
- ❌ Modelos sem testes mínimos
- ❌ Lógica de negócio em Bronze
- ❌ Surrogate key não-composta em multi-tenant
- ❌ `incremental` sem filtro de data (full scan toda execução)
- ❌ Ref via string raw (`from "{{ database }}.{{ schema }}.x"`)
- ❌ `pre_hook` que muda dados (deve ser idempotente; preferir model)

---

## Comandos Úteis

```bash
# Build apenas Silver
dbt build --select tag:silver

# Build downstream de um source
dbt build --select source:bronze.vendas+

# Build Gold em modo defer (usa Silver de prod)
dbt build --select gold --defer --state ./manifest-prd

# Compile only (sem rodar)
dbt compile --select fct_vendas

# Source freshness
dbt source freshness
```

---

## Tags Recomendadas

Em `schema.yml`:

```yaml
models:
  - name: dim_clientes
    config:
      tags: ['silver', 'dim', 'comercial']
```

Permite seleção: `dbt build --select tag:dim`.

---

## Referências
- [naming-conventions](naming-conventions.instructions.md) — nomes de tabelas/colunas
- [data-modeling](data-modeling.instructions.md) — Kimball star schema
- [data-quality](data-quality.instructions.md) — testes e qualidade
- [sql-athena](sql-athena.instructions.md) — dialeto Trino
- [cost-awareness](cost-awareness.instructions.md) — custo Athena
