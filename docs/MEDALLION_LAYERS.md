# Camadas Medallion — Detalhamento

Arquitetura de 4 camadas: **Bronze → Silver → Gold → Platinum**.

| Camada | Storage | Materialização | Total Modelos | Função |
|---|---|---|---|---|
| Bronze | S3 (Parquet) | Glue tables externas | 23 tabelas (8 datamarts) | Raw, particionado por `tenant_id` + data |
| Silver | S3 + Iceberg | `incremental` (merge) | **21** | Limpeza, padronização, unificação multi-tenant |
| Gold | S3 + Iceberg | `incremental` + `table` | **18** (9 dims + 7 facts + 2 DREs) | Star schema Kimball |
| Platinum | S3 + Iceberg | `incremental` / `table` | **6** | Visões de negócio por unidade |

---

## Bronze — Raw Storage

**Não é gerenciada pelo dbt** — apenas declarada como `sources` em `dbt/models/sources.yml`.

### Estrutura

```
s3://elt-pipeline-bronze-${env}/
├── comercial/
│   ├── clientes/{tenant_id}/{year}/{month}/{day}/*.parquet
│   ├── vendedores/...
│   ├── pedidos/...
│   ├── itens_pedido/...
│   └── vendas/...
├── financeiro/
│   ├── titulos_pagar/...
│   ├── titulos_receber/...
│   ├── baixas/...
│   └── condpag/...
├── controladoria/
├── logistica/
├── suprimentos/
├── corporativo/
├── industrial/
└── contabilidade/
```

### Partition Projection (Glue)

Cada tabela Bronze é registrada com partition projection no Glue Catalog:

```sql
CREATE EXTERNAL TABLE bronze.vendas (
    venda_id STRING,
    data_venda TIMESTAMP,
    ...
)
PARTITIONED BY (tenant_id STRING, year INT, month INT, day INT)
STORED AS PARQUET
LOCATION 's3://elt-pipeline-bronze-${env}/comercial/vendas/'
TBLPROPERTIES (
    'projection.enabled' = 'true',
    'projection.tenant_id.type' = 'enum',
    'projection.tenant_id.values' = 'unit_01,unit_02,unit_03,unit_04,unit_05',
    'projection.year.type' = 'integer',
    'projection.year.range' = '2024,2030',
    'projection.month.type' = 'integer',
    'projection.month.range' = '1,12',
    'projection.day.type' = 'integer',
    'projection.day.range' = '1,31',
    'storage.location.template' = 's3://...vendas/tenant_id=${tenant_id}/year=${year}/month=${month}/day=${day}/'
);
```

---

## Silver — Padronização e Unificação

**Objetivo**: deduplicar, padronizar tipos, normalizar nomes, **unificar 5 tenants em uma única tabela**.

### 21 Modelos Silver

| Datamart | Modelo | Função |
|---|---|---|
| comercial | `silver_dw_clientes` | Clientes consolidados por tenant |
| comercial | `silver_dw_vendedores` | Vendedores |
| comercial | `silver_dw_produtos` | Produtos / SKUs |
| comercial | `silver_dw_vendas` | Pedidos de venda |
| comercial | `silver_dw_itens_pedido` | Itens de pedido |
| suprimentos | `silver_dw_fornecedores` | Fornecedores |
| suprimentos | `silver_dw_ordens_compra` | Ordens de compra |
| corporativo | `silver_dw_empresas` | Empresas / filiais |
| corporativo | `silver_dw_departamentos` | Departamentos |
| corporativo | `silver_dw_funcionarios` | Colaboradores |
| industrial | `silver_dw_materias_primas` | Matérias-primas |
| industrial | `silver_dw_ordens_producao` | Ordens de produção |
| logistica | `silver_dw_filiais` | Filiais logísticas |
| logistica | `silver_dw_transportadoras` | Transportadoras |
| logistica | `silver_dw_expedicao` | Expedições / entregas |
| controladoria | `silver_dw_centros_custos` | Centros de custo contábil |
| controladoria | `silver_dw_projetos` | Projetos |
| controladoria | `silver_dw_orcamento` | Orçamento por projeto |
| financeiro | `silver_dw_titulos_financeiros` | Títulos a pagar/receber (UNION ALL) |
| contabilidade | `silver_dw_plano_contas` | Plano de contas |
| contabilidade | `silver_dw_lancamentos` | Lançamentos contábeis |

### Padrão de Modelo Silver

```sql
{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['tenant_id', 'venda_id'],
    on_schema_change='append_new_columns',
    table_type='iceberg',
    format='parquet'
  )
}}

WITH source_data AS (
    SELECT * FROM {{ source('bronze', 'vendas') }}
    {% if is_incremental() %}
      WHERE updated_at >= (SELECT MAX(updated_at) - INTERVAL '1' DAY FROM {{ this }})
    {% endif %}
),

cleaned AS (
    SELECT
        tenant_id,
        venda_id,
        CAST(data_venda AS DATE) AS dt_venda,
        UPPER(TRIM(cliente_id)) AS cliente_id,
        UPPER(TRIM(produto_id)) AS produto_id,
        CAST(quantidade AS DECIMAL(18, 4)) AS qtd_vendida,
        CAST(valor_total AS DECIMAL(18, 2)) AS vlr_total,
        UPPER(status) AS status_venda,
        created_at,
        updated_at,
        CURRENT_TIMESTAMP AS _dbt_loaded_at
    FROM source_data
    WHERE venda_id IS NOT NULL
)

SELECT * FROM cleaned
```

### Transformações Comuns

- Trim + UPPER em strings categóricas
- Cast explícito de tipos (DECIMAL para valores monetários)
- Coalesce de campos com nomes diferentes entre tenants
- Filtro de registros com PK nula
- Audit column `_dbt_loaded_at`

---

## Gold — Star Schema

**Objetivo**: modelar dimensions e facts conforme Kimball; chaves substitutas (surrogate keys) para todas as dimensions.

### 18 Modelos Gold

#### 9 Dimensions
1. `dim_calendrio` (gerada via Jinja — 1.461 dias, sem source Bronze)
2. `dim_clientes`
3. `dim_produtos`
4. `dim_vendedores`
5. `dim_fornecedores`
6. `dim_empresas`
7. `dim_funcionarios`
8. `dim_centros_custos`
9. `dim_plano_contas`

#### 7 Facts
1. `fct_vendas`
2. `fct_ordens_compra`
3. `fct_ordens_producao`
4. `fct_expedicao`
5. `fct_orcamento_projetos`
6. `fct_titulo_financeiro`
7. `fct_lancamentos`

#### 2 DREs (analytics)
1. `dre_contabil`
2. `dre_gerencial`

### Padrão Dimension

```sql
{{
  config(
    materialized='incremental',
    unique_key='cliente_sk',
    table_type='iceberg'
  )
}}

WITH src AS (
    SELECT * FROM {{ ref('silver_dw_clientes') }}
)

SELECT
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'cliente_id']) }} AS cliente_sk,
    tenant_id,
    cliente_id,
    nome_cliente,
    cidade,
    uf,
    pais,
    cnpj_cpf,
    tipo_pessoa,
    segmento,
    _dbt_loaded_at
FROM src
```

### Padrão Fact

```sql
{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['tenant_id', 'venda_id'],
    table_type='iceberg'
  )
}}

WITH 
vendas AS (SELECT * FROM {{ ref('silver_dw_venda') }}),
clientes AS (SELECT * FROM {{ ref('dim_clientes') }}),
produtos AS (SELECT * FROM {{ ref('dim_produtos') }}),
vendedores AS (SELECT * FROM {{ ref('dim_vendedor') }}),
empresas AS (SELECT * FROM {{ ref('dim_empresas') }}),
calendario AS (SELECT * FROM {{ ref('dim_calendrio') }})

SELECT
    {{ dbt_utils.generate_surrogate_key(['v.tenant_id', 'v.venda_id']) }} AS venda_sk,
    v.tenant_id,
    v.venda_id,
    cal.data_id,
    cli.cliente_sk,
    prd.produto_sk,
    vnd.vendedor_sk,
    emp.empresa_sk,
    v.qtd_vendida,
    v.vlr_total,
    v.status_venda,
    v.updated_at,
    CURRENT_TIMESTAMP AS _dbt_loaded_at
FROM vendas v
LEFT JOIN clientes cli ON cli.tenant_id = v.tenant_id AND cli.cliente_id = v.cliente_id
LEFT JOIN produtos prd ON prd.tenant_id = v.tenant_id AND prd.produto_id = v.produto_id
LEFT JOIN vendedores vnd ON vnd.tenant_id = v.tenant_id AND vnd.vendedor_id = v.vendedor_id
LEFT JOIN empresas emp ON emp.tenant_id = v.tenant_id AND emp.empresa_id = v.empresa_id
LEFT JOIN calendario cal ON cal.data_completa = v.dt_venda
```

---

## Platinum — Visões de Negócio

**Objetivo**: produzir visões prontas para BI, separadas por unidade de negócio. Materializadas como Iceberg tables para consultas eficientes com predicate pushdown.

### 6 Modelos Platinum

| Modelo | Derivado de | Descrição | Material. |
|---|---|---|---|
| `controle_inadimplentes` | `fct_titulo_financeiro` | Títulos com `ds_situacao_titulo = 'VENCIDO'` | incremental |
| `dre_contabil_unit_01` | `dre_contabil` | DRE Contábil filtrado `tenant_id = 'unit_01'` | table |
| `dre_contabil_unit_02` | `dre_contabil` | DRE Contábil filtrado `tenant_id = 'unit_02'` | table |
| `dre_gerencial_unit_01` | `dre_gerencial` | DRE Gerencial filtrado `tenant_id = 'unit_01'` | table |
| `dre_gerencial_unit_02` | `dre_gerencial` | DRE Gerencial filtrado `tenant_id = 'unit_02'` | table |
| `dim_produtos_otimizada` | `dim_produtos` | Subconjunto de colunas para catálogo de produtos | table |

### Padrão Platinum (View por Unidade)

```sql
{{
  config(
    materialized='view'
  )
}}

SELECT *
FROM {{ ref('dre_contabil') }}
WHERE tenant_id = 'unit_01'
```

### Padrão Platinum (Visão Cross-Tenant)

```sql
{{
  config(
    materialized='table',
    table_type='iceberg'
  )
}}

WITH titulos_vencidos AS (
    SELECT
        tenant_id,
        cliente_sk,
        SUM(vlr_titulo) AS vlr_inadimplente,
        SUM(dias_atraso) / COUNT(*) AS dias_atraso_medio,
        COUNT(*) AS qtd_titulos_vencidos
    FROM {{ ref('fct_titulo_financeiro') }}
    WHERE dias_atraso > 30
      AND status_titulo = 'ABERTO'
    GROUP BY tenant_id, cliente_sk
)

SELECT
    t.*,
    c.nome_cliente,
    c.cnpj_cpf,
    CURRENT_TIMESTAMP AS _dbt_loaded_at
FROM titulos_vencidos t
LEFT JOIN {{ ref('dim_clientes') }} c USING (tenant_id, cliente_sk)
```

---

## Sources & Seeds

### Sources (`dbt/models/sources.yml`)
- 40 tabelas registradas (8 datamarts × 5 tenants efetivamente unidos via partition)
- `freshness` configurado: warn 24h, error 48h

### Seeds (`dbt/seeds/`)
- `dim_calendario.csv` — calendário base (alternativa a macro)
- `mapeamento_estrutura_dre.csv` — estrutura DRE para joins
- `metas_anuais.csv` — orçamento anual por unidade

---

## Estratégia de Materialização

| Camada | Materialização | Justificativa |
|---|---|---|
| Bronze | external (Glue table) | Raw, sem reprocessamento |
| Silver | `incremental` + Iceberg merge | Volume alto, evita full refresh |
| Gold (dims) | `incremental` (SCD0/SCD1) | Mudanças pontuais |
| Gold (facts) | `incremental` + Iceberg merge | Volume alto, late-arriving data |
| Gold (DRE) | `table` | Recálculo completo é barato |
| Platinum (views) | `view` | Zero storage, query-time compute |
| Platinum (tables) | `table` | Quando view fica lenta |

---

## Testes Por Camada (cobertura mínima)

```yaml
# silver: schema.yml
models:
  - name: silver_dw_venda
    columns:
      - name: venda_id
        tests:
          - not_null
      - name: tenant_id
        tests:
          - accepted_values:
              values: ['unit_01', 'unit_02', 'unit_03', 'unit_04', 'unit_05']

# gold: schema.yml
models:
  - name: fct_vendas
    columns:
      - name: venda_sk
        tests:
          - not_null
          - unique
      - name: cliente_sk
        tests:
          - relationships:
              to: ref('dim_clientes')
              field: cliente_sk
```

---

## Documentação Lineage

Após `dbt docs generate`:
- Lineage gráfico interativo
- Descrição de cada modelo + coluna
- Resultado de testes (passou/falhou + histórico)
- Hospedado em GitHub Pages (Sprint 8)
