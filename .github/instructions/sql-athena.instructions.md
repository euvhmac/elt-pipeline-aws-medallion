---
applyTo: '**/*.sql'
---

# SQL — Athena (Trino) Dialect

> Padrões SQL para Amazon Athena engine v3 (baseado em Trino). Aplicável a todos arquivos `.sql`.

---

## Engine

- **Athena engine v3** = Trino fork
- **Documentação oficial**: [docs.aws.amazon.com/athena](https://docs.aws.amazon.com/athena/) e [trino.io/docs](https://trino.io/docs/)
- **NÃO confundir com**: Spark SQL, Presto v0.x, MySQL, PostgreSQL

---

## Dialeto Trino — Diferenças Críticas vs Spark/Presto Antigo

### Datas / Timestamps

| Operação | Spark SQL | Trino (Athena v3) |
|---|---|---|
| Parse string → date | `to_date('2024-01-01', 'yyyy-MM-dd')` | `date_parse('2024-01-01', '%Y-%m-%d')` ou `DATE '2024-01-01'` |
| Parse string → timestamp | `to_timestamp(...)` | `date_parse(...)` (formato C-like) |
| Format date | `date_format(d, 'yyyy-MM')` | `date_format(d, '%Y-%m')` |
| Add interval | `date_add(d, 1)` | `d + INTERVAL '1' DAY` |
| Diff days | `datediff(end, start)` | `date_diff('day', start, end)` |
| Truncate | `date_trunc('month', d)` | `date_trunc('month', d)` ✅ igual |
| Current | `current_date` | `CURRENT_DATE` ✅ igual |

### Strings

| Operação | Trino | Notas |
|---|---|---|
| Concatenação | `concat(a, b)` ou `a \|\| b` | `\|\|` preferido |
| Trim | `trim(s)`, `ltrim(s)`, `rtrim(s)` | |
| Replace | `replace(s, 'a', 'b')` | |
| Regex match | `regexp_like(s, 'pattern')` | retorna boolean |
| Regex extract | `regexp_extract(s, 'pattern', 1)` | grupo 1 |
| Length | `length(s)` | |
| Upper/Lower | `upper(s)`, `lower(s)` | |
| Split | `split(s, ',')` | retorna array |

### Casts

```sql
-- ✅ Trino style
CAST('123' AS INTEGER)
CAST('2024-01-01' AS DATE)
TRY_CAST(s AS DECIMAL(18,2))  -- retorna NULL se falhar

-- ❌ Spark style (não funciona em Athena)
INT('123')
'123'::int  -- syntax PostgreSQL
```

### NULLs

```sql
COALESCE(a, b, c)
NULLIF(a, b)              -- NULL se a=b
IS NULL / IS NOT NULL
IF(condition, then, else)  -- equivalente a CASE WHEN
```

---

## Partition Pruning — OBRIGATÓRIO

Athena cobra por **bytes scanned**. Toda query deve aproveitar partições.

### ✅ Predicate pushdown

```sql
SELECT *
FROM gold.fct_vendas
WHERE tenant_id = 'unit_01'                    -- ✅ partition column
  AND dt_venda >= DATE '2024-01-01'            -- ✅ partition column (month())
  AND dt_venda < DATE '2024-02-01'
```

### ❌ Sem pruning (full scan caro)

```sql
SELECT *
FROM gold.fct_vendas
WHERE EXTRACT(YEAR FROM dt_venda) = 2024       -- ❌ função no predicate
  AND UPPER(tenant_id) = 'UNIT_01'             -- ❌ função no predicate
```

### Workgroup safety

Athena workgroup configurado com `bytes_scanned_cutoff_per_query=10GB` (default deste projeto). Queries que excedem **falham automaticamente**.

---

## Tipos de Dados

### Monetários — SEMPRE `DECIMAL`

```sql
-- ✅ Correto
vlr_total       DECIMAL(18,2)
vlr_unitario    DECIMAL(18,4)  -- mais precisão para unit price
pct_desconto    DECIMAL(5,2)

-- ❌ NUNCA
vlr_total       DOUBLE          -- arredondamentos imprevisíveis
vlr_total       FLOAT           -- pior ainda
```

### Quantidades

```sql
qtd_vendida     DECIMAL(18,4)   -- aceita frações (kg, m³)
qtd_pedidos     INTEGER         -- contagem inteira
```

### Identificadores

```sql
tenant_id       VARCHAR         -- 'unit_01' etc
cliente_id      VARCHAR         -- ID do source
cliente_sk      VARCHAR(32)     -- MD5 hash dbt_utils
```

### Datas

```sql
dt_venda        DATE
created_at      TIMESTAMP       -- com fração de segundos
_dbt_loaded_at  TIMESTAMP
```

### Booleans

```sql
is_active       BOOLEAN
```

---

## CTEs > Subqueries

### ✅ Legível e otimizável

```sql
WITH vendas_filtradas AS (
  SELECT *
  FROM silver_dw_vendas
  WHERE tenant_id = 'unit_01'
    AND dt_venda >= DATE '2024-01-01'
),

agregado AS (
  SELECT
    cliente_id,
    SUM(vlr_total) AS vlr_total_periodo
  FROM vendas_filtradas
  GROUP BY cliente_id
)

SELECT *
FROM agregado
WHERE vlr_total_periodo > 1000
```

### ❌ Subquery aninhada

```sql
SELECT *
FROM (
  SELECT cliente_id, SUM(vlr_total) AS total
  FROM (
    SELECT * FROM silver_dw_vendas WHERE tenant_id = 'unit_01'
  )
  GROUP BY cliente_id
) WHERE total > 1000
```

---

## Window Functions — Padrão Multi-Tenant

**Sempre incluir `tenant_id` em `PARTITION BY`** para garantir isolamento:

```sql
SELECT
  venda_id,
  cliente_id,
  vlr_total,
  ROW_NUMBER() OVER (
    PARTITION BY tenant_id, cliente_id
    ORDER BY dt_venda DESC
  ) AS rn,
  SUM(vlr_total) OVER (
    PARTITION BY tenant_id, cliente_id
    ORDER BY dt_venda
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS vlr_acumulado
FROM silver_dw_vendas
```

### Funções comuns

- `ROW_NUMBER()` — numeração sequencial
- `RANK()` / `DENSE_RANK()` — ranking
- `LAG(col, n)` / `LEAD(col, n)` — valor anterior/próximo
- `FIRST_VALUE` / `LAST_VALUE` — primeiro/último valor
- `SUM/AVG/MIN/MAX OVER (...)` — agregações móveis

---

## EXPLAIN ANALYZE — Para Modelos Caros

Antes de mergear modelo Gold/Platinum complexo:

```sql
EXPLAIN ANALYZE
SELECT ... -- query do modelo
```

Verificar:
- **Bytes scanned** (idealmente < 1GB para modelos rotineiros)
- **Stage com mais tempo** (otimizar joins/aggregations)
- **Partition pruning aplicado** (procurar `Predicate: tenant_id = ...`)

Anexar resultado em PR de modelo Gold complexo (ver template).

---

## Iceberg — Operações Específicas

### Time travel

```sql
-- Snapshot anterior
SELECT * FROM gold.fct_vendas FOR VERSION AS OF 1234567890;

-- Timestamp específico
SELECT * FROM gold.fct_vendas FOR TIMESTAMP AS OF TIMESTAMP '2024-01-01 00:00:00';
```

### MERGE

```sql
MERGE INTO gold.fct_vendas t
USING staging.fct_vendas_new s
ON t.tenant_id = s.tenant_id AND t.venda_id = s.venda_id
WHEN MATCHED THEN UPDATE SET vlr_total = s.vlr_total
WHEN NOT MATCHED THEN INSERT (...) VALUES (...);
```

### OPTIMIZE / VACUUM (manutenção mensal)

```sql
OPTIMIZE gold.fct_vendas REWRITE DATA USING BIN_PACK;
VACUUM gold.fct_vendas;
```

---

## Joins — Padrões

```sql
-- ✅ Explicit JOIN type
FROM fct_vendas v
INNER JOIN dim_clientes c
  ON v.tenant_id = c.tenant_id
  AND v.cliente_sk = c.cliente_sk
LEFT JOIN dim_produtos p
  ON v.tenant_id = p.tenant_id
  AND v.produto_sk = p.produto_sk

-- ❌ Comma join (legado SQL-89, evitar)
FROM fct_vendas v, dim_clientes c
WHERE v.cliente_sk = c.cliente_sk
```

**Regra multi-tenant**: todo JOIN entre fact e dim inclui `tenant_id` no `ON`.

---

## Aggregations — Padrões

```sql
-- ✅ COUNT(*) para linhas
SELECT COUNT(*) FROM fct_vendas;

-- ✅ COUNT(DISTINCT col) para distintos
SELECT COUNT(DISTINCT cliente_id) FROM fct_vendas;

-- ✅ APPROX_DISTINCT para grandes volumes (faster)
SELECT APPROX_DISTINCT(cliente_id) FROM fct_vendas;

-- ✅ FILTER em agregações condicionais (Trino)
SELECT
  SUM(vlr_total) FILTER (WHERE status = 'pago') AS vlr_pago,
  SUM(vlr_total) FILTER (WHERE status = 'pendente') AS vlr_pendente
FROM fct_titulo_financeiro
```

---

## Anti-Patterns SQL

- ❌ `SELECT *` em models Gold/Platinum
- ❌ Função em coluna de partition (`UPPER(tenant_id)`, `EXTRACT(YEAR FROM dt)`)
- ❌ `DOUBLE`/`FLOAT` para dinheiro
- ❌ Subqueries quando CTE resolve
- ❌ JOIN sem `tenant_id` em modelos multi-tenant
- ❌ `WHERE 1=1` (placeholder de IDE) deixado no commit
- ❌ Hardcoded values sem comentário explicando
- ❌ Uppercase em identificadores (`SELECT CLIENTE_ID FROM...`)
- ❌ `LIMIT` em production model (prefere `WHERE`)

---

## Style Guide

```sql
-- ✅ Padrão deste repositório
SELECT
  v.tenant_id,
  v.venda_id,
  c.cliente_id,
  v.dt_venda,
  v.vlr_total
FROM {{ ref('silver_dw_vendas') }} v
LEFT JOIN {{ ref('dim_clientes') }} c
  ON v.tenant_id = c.tenant_id
  AND v.cliente_id = c.cliente_id
WHERE v.tenant_id = 'unit_01'
  AND v.dt_venda >= DATE '2024-01-01'
ORDER BY v.dt_venda DESC
```

Regras:
- **Keywords UPPERCASE**: `SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`
- **Identifiers lowercase snake_case**: `cliente_id`, `vlr_total`
- **Indentação 2 spaces** (configurar `sqlfluff`)
- **Vírgula no início** (opcional, mas consistente)
- **Aliases curtos e claros**: `v` para vendas, `c` para clientes
- **Linha em branco** entre CTEs

---

## Validação CI (Sprint 7)

- `sqlfluff lint --dialect athena dbt/models/`
- `sqlfluff format --dialect athena --in-place dbt/models/` (auto-fix)
- Pre-commit hook bloqueia SQL inválido

---

## Referências
- [Trino docs](https://trino.io/docs/current/)
- [Athena SQL reference](https://docs.aws.amazon.com/athena/latest/ug/ddl-sql-reference.html)
- [dbt instructions](dbt.instructions.md)
- [naming-conventions](naming-conventions.instructions.md)
