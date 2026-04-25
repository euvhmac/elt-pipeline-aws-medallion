---
applyTo: '**/{schema,sources,properties}.yml'
---

# Data Quality — Testing Pyramid

> Padrões de testes dbt e qualidade de dados. Aplicável a `schema.yml`, `sources.yml`, `properties.yml`.

---

## Pirâmide de Testes

```
                  ╱╲
                 ╱E2E╲              ← Singular SQL tests (raros, complexos)
                ╱──────╲
               ╱ dbt-   ╲           ← dbt-expectations (distribuição, range)
              ╱  expect  ╲
             ╱────────────╲
            ╱ Relationships╲        ← FK integrity entre dims/facts
           ╱────────────────╲
          ╱  Schema (PKs/FKs) ╲     ← not_null, unique, accepted_values (base)
         ╱──────────────────────╲
```

**Regra**: 100% dos PKs e FKs em Gold têm testes obrigatórios.

---

## Schema Tests Mínimos

### Toda dim Gold tem:

```yaml
columns:
  - name: <entidade>_sk
    description: "Surrogate key composta de [tenant_id, <natural_key>]"
    tests:
      - not_null
      - unique
  - name: tenant_id
    description: "Identificador da unidade de negócio"
    tests:
      - not_null
      - accepted_values:
          values: ['unit_01', 'unit_02', 'unit_03', 'unit_04', 'unit_05']
  - name: <natural_key>
    description: "Chave natural (vinda do source)"
    tests:
      - not_null
```

### Toda fact Gold tem:

```yaml
columns:
  - name: <evento>_sk
    description: "Surrogate key composta"
    tests:
      - not_null
      - unique
  - name: tenant_id
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
  - name: dt_<evento>
    description: "Data do evento"
    tests:
      - not_null
  - name: vlr_total
    description: "Valor total (DECIMAL(18,2))"
    tests:
      - not_null
      - dbt_utils.expression_is_true:
          expression: ">= 0"
```

---

## Severity

```yaml
tests:
  - not_null:
      severity: error      # bloqueia run em produção (default em PKs/FKs)
  - dbt_utils.expression_is_true:
      expression: "vlr_total < 1000000"
      severity: warn       # apenas alerta (outliers de negócio)
```

### Regras de severity
- **`error` (default)** em: PKs, FKs, `tenant_id`, datas obrigatórias, valores monetários `not_null`
- **`warn`** em: outliers de negócio, freshness de fontes secundárias, expectativas heurísticas

---

## Tests por Categoria

### 1. Schema tests (dbt-core nativos)

```yaml
tests:
  - not_null
  - unique
  - accepted_values:
      values: ['unit_01', 'unit_02', 'unit_03', 'unit_04', 'unit_05']
  - relationships:
      to: ref('dim_clientes')
      field: cliente_sk
```

### 2. dbt_utils tests

```yaml
tests:
  # Composite uniqueness (multi-tenant)
  - dbt_utils.unique_combination_of_columns:
      combination_of_columns: ['tenant_id', 'venda_id', 'produto_id']

  # Expression-based
  - dbt_utils.expression_is_true:
      expression: "vlr_total >= 0"
  - dbt_utils.expression_is_true:
      expression: "qtd_vendida > 0"

  # Equal rowcount
  - dbt_utils.equal_rowcount:
      compare_model: ref('silver_dw_vendas')
```

### 3. dbt-expectations tests

```yaml
tests:
  # Volume sanity check
  - dbt_expectations.expect_table_row_count_to_be_between:
      min_value: 1000
      max_value: 10000000

  # Distribution
  - dbt_expectations.expect_column_values_to_be_between:
      min_value: 0
      max_value: 1000000
      column: vlr_total

  # Type/format
  - dbt_expectations.expect_column_values_to_match_regex:
      regex: '^unit_0[1-5]$'
      column: tenant_id

  # Pareto / outliers
  - dbt_expectations.expect_column_quantile_values_to_be_between:
      quantile: 0.99
      min_value: 0
      max_value: 100000
      column: vlr_total
```

### 4. Singular tests (custom SQL)

Localização: `dbt/tests/`. Convenção: arquivo `.sql` retorna linhas que **violam** a regra.

```sql
-- dbt/tests/test_no_overlap_dre_periods.sql
-- Verifica que períodos de DRE não se sobrepõem por tenant
WITH overlaps AS (
  SELECT
    tenant_id,
    ano_mes,
    COUNT(*) AS dup_count
  FROM {{ ref('dre_contabil') }}
  GROUP BY tenant_id, ano_mes
  HAVING COUNT(*) > 1
)
SELECT * FROM overlaps
```

---

## Source Freshness

**Obrigatório** em todas sources Bronze:

```yaml
sources:
  - name: bronze
    database: awsdatacatalog
    schema: bronze
    loaded_at_field: _dbt_loaded_at  # default da camada
    freshness:
      warn_after: { count: 24, period: hour }
      error_after: { count: 48, period: hour }

    tables:
      - name: vendas
        description: "Vendas raw geradas pelo synthetic source"
        # override por tabela quando necessário
        freshness:
          warn_after: { count: 12, period: hour }
          error_after: { count: 24, period: hour }
```

### CI gate
- `dbt source freshness` roda em workflow scheduled
- Failure dispara SNS → Slack

---

## Volume Tests (dbt-expectations)

**Toda fact Gold** deve ter test de volume mínimo:

```yaml
- dbt_expectations.expect_table_row_count_to_be_between:
    min_value: 100        # nunca deve ficar abaixo (sanity)
    max_value: 100000000  # nunca deve explodir (anti-bug)
```

Ajustar valores por modelo após observar baseline.

---

## Generic Tests Customizados

Localização: `dbt/tests/generic/<nome>.sql`. Usados via:

```yaml
columns:
  - name: vlr_total
    tests:
      - is_positive_decimal  # custom test
```

Implementação:

```sql
-- dbt/tests/generic/is_positive_decimal.sql
{% test is_positive_decimal(model, column_name) %}

SELECT *
FROM {{ model }}
WHERE {{ column_name }} < 0

{% endtest %}
```

---

## Documentação obrigatória

```yaml
models:
  - name: fct_vendas
    description: |
      Tabela fato de vendas. 1 linha por item de pedido.
      Inclui valores monetários, quantidades e referências
      para dim_clientes, dim_produtos, dim_vendedor.

      **Grain**: tenant_id × venda_id × produto_id
      **Refresh**: incremental merge, lookback 1 dia
      **Particionamento**: tenant_id, month(dt_venda)

    config:
      meta:
        owner: vhmac
        layer: gold
        grain: "tenant_id × venda_id × produto_id"
        contains_pii: false

    columns:
      - name: venda_sk
        description: "Surrogate key composta"
        tests:
          - not_null
          - unique
      ...
```

---

## Test Selection (CI)

```bash
# Todos testes
dbt test

# Apenas testes em Gold
dbt test --select tag:gold

# Testes downstream de um model
dbt test --select fct_vendas+

# Apenas singular tests
dbt test --select test_type:singular

# Apenas schema tests
dbt test --select test_type:generic

# Severity error only (bloqueio CI)
dbt test --severity error
```

---

## Anti-Patterns

- ❌ Modelo Gold sem testes de PK/FK
- ❌ FK sem `relationships`
- ❌ `severity: warn` em PK (deve ser `error`)
- ❌ Source sem `freshness`
- ❌ Test sem `description` (em testes singulares custosos)
- ❌ Volume test ausente em fact (catastrophe undetected)
- ❌ `accepted_values` faltando em `tenant_id`
- ❌ Negócio crítico sem singular test (DRE sem soma = 100%)

---

## Métricas de Qualidade (Observabilidade)

Após cada `dbt test`, exportar métricas para CloudWatch (Sprint 5):
- `tests_total` (count)
- `tests_passed` (count)
- `tests_failed` (count)
- `tests_warn` (count)
- `tests_duration_seconds` (gauge)

Dashboard CloudWatch: `dbt-quality-overview`.

---

## Referências
- [dbt Tests](https://docs.getdbt.com/docs/build/data-tests)
- [dbt-expectations](https://github.com/calogica/dbt-expectations)
- [dbt-utils](https://github.com/dbt-labs/dbt-utils)
- [data-modeling](data-modeling.instructions.md)
- [observability](observability.instructions.md)
