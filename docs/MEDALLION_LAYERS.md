# Camadas Medallion — Detalhamento

Arquitetura de 4 camadas: **Bronze → Silver → Gold → Platinum**.

| Camada | Storage | Materialização | Total Modelos | Função |
|---|---|---|---|---|
| Bronze | S3 (Parquet) | Glue tables externas | 40 (8 datamarts × 5 tenants) | Raw, particionado |
| Silver | S3 + Iceberg | `incremental` (merge) | 30 | Limpeza, padronização, unificação |
| Gold | S3 + Iceberg | `incremental` + `table` | 16 | Star schema (8 dims + 6 facts + 2 DREs) |
| Platinum | S3 + Iceberg | `view` | 9 | Visões de negócio por unidade |

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

### 30 Modelos Silver

Inspirados na estrutura original do baseline interno corporativo:

| # | Modelo | Função |
|---|---|---|
| 1 | `silver_dw_areageo` | Áreas geográficas |
| 2 | `silver_dw_ccusto_contabil` | Centros de custo contábil |
| 3 | `silver_dw_cidade` | Cidades / municípios |
| 4 | `silver_dw_classe` | Classes de produto |
| 5 | `silver_dw_clientes` | Clientes consolidados |
| 6 | `silver_dw_condpag` | Condições de pagamento |
| 7 | `silver_dw_conta_contabil` | Plano de contas |
| 8 | `silver_dw_danfe` | Cabeçalho de NF-e (DANFE) |
| 9 | `silver_dw_danfite` | Itens de NF-e |
| 10 | `silver_dw_devolucao` | Devoluções |
| 11 | `silver_dw_embalagem` | Embalagens |
| 12 | `silver_dw_empresa` | Empresas / filiais |
| 13 | `silver_dw_familia` | Famílias de produto |
| 14 | `silver_dw_filial` | Filiais (granular) |
| 15 | `silver_dw_grupo` | Grupos de produto |
| 16 | `silver_dw_item` | Itens / SKUs |
| 17 | `silver_dw_lancamento_origem` | Lançamentos contábeis origem |
| 18 | `silver_dw_linha` | Linhas de produto |
| 19 | `silver_dw_marca` | Marcas |
| 20 | `silver_dw_motorista` | Motoristas |
| 21 | `silver_dw_pais` | Países |
| 22 | `silver_dw_pedido` | Cabeçalho de pedido |
| 23 | `silver_dw_pedidoit` | Itens de pedido |
| 24 | `silver_dw_produto` | Produtos consolidados |
| 25 | `silver_dw_projeto` | Projetos |
| 26 | `silver_dw_titulo` | Títulos financeiros |
| 27 | `silver_dw_transportadora` | Transportadoras |
| 28 | `silver_dw_uf` | Unidades federativas |
| 29 | `silver_dw_vendedor` | Vendedores |
| 30 | `silver_dw_venda` | Vendas detalhadas |

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

### 16 Modelos Gold

#### 8 Dimensions
1. `dim_calendrio` (gerada via macro, sem source)
2. `dim_clientes`
3. `dim_produtos`
4. `dim_empresas`
5. `dim_centros_custos`
6. `dim_contas_contabeis`
7. `dim_condpag`
8. `dim_vendedor`
9. `dim_estrutura_dre_contabil`

#### 6 Facts
1. `fct_vendas`
2. `fct_faturamento`
3. `fct_devolucao`
4. `fct_titulo_financeiro`
5. `fct_lancamentos_origem`
6. `fct_projetos_consolidados`

#### 2 DREs (consolidados)
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

**Objetivo**: produzir visões prontas para BI, separadas por unidade de negócio. Materializadas como `view` para zero custo de armazenamento.

### 9 Modelos Platinum

| Modelo | Descrição | Material. |
|---|---|---|
| `dre_contabil_unit_01` | DRE Contábil Unidade 01 | view |
| `dre_contabil_unit_02` | DRE Contábil Unidade 02 | view |
| `dre_gerencial_unit_01` | DRE Gerencial Unidade 01 | view |
| `dre_gerencial_unit_02` | DRE Gerencial Unidade 02 | view |
| `dim_estrutura_dre_contabil_unit_01` | Estrutura DRE específica Unidade 01 | view |
| `dim_estrutura_dre_contabil_unit_02` | Estrutura DRE específica Unidade 02 | view |
| `dim_produtos_otimizada` | Produtos enriquecidos (todas as unidades) | table |
| `controle_inadimplentes` | Inadimplência > 30 dias | table |
| _(reservado)_ | _(slot para nova visão de negócio)_ | — |

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
