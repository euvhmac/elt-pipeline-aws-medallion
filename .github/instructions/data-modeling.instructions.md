---
applyTo: 'dbt/models/{gold,platinum}/**'
---

# Data Modeling — Kimball Star Schema

> Padrões de modelagem dimensional para camadas Gold (star schema) e Platinum (visões de negócio).

---

## Filosofia

**Kimball Dimensional Modeling** com adaptação multi-tenant:
- **Star schema** > snowflake (joins simples, performance Athena)
- **Conformed dimensions** (mesma `dim_clientes` usada em múltiplos facts)
- **Surrogate keys compostas** com `tenant_id`
- **Grain explicitamente documentado** em cada fact

---

## Tipos de Tabela

### Dimensions (`dim_*`)
Descrevem **entidades** com atributos descritivos. Mudam pouco.

Exemplos no projeto:
- `dim_clientes`, `dim_produtos`, `dim_empresas`, `dim_vendedor`
- `dim_centros_custos`, `dim_condpag`, `dim_contas_contabeis`
- `dim_estrutura_dre_contabil`

### Facts (`fct_*`)
Registram **eventos/medições** com chaves para dims + medidas numéricas.

Exemplos:
- `fct_vendas`, `fct_devolucao`, `fct_titulo_financeiro`
- `fct_lancamentos_origem`, `fct_faturamento`, `fct_projetos_consolidados`

### DRE (`dre_*`)
Tabelas analíticas pré-calculadas (Demonstrações de Resultado).

- `dre_contabil`, `dre_gerencial` (Gold)
- `dre_contabil_unit_01`, `dre_gerencial_unit_01`, ... (Platinum)

### Platinum
Visões finais por unidade ou conceito de negócio:
- `<modelo>_unit_NN` para visões por tenant
- `controle_inadimplentes`, `dim_produtos_otimizada` (cross-cutting)

---

## Grain — Definir SEMPRE

Toda fact tem **um único grain documentado**:

```sql
-- Modelo: fct_vendas
-- Grão: 1 linha = 1 item de pedido (split de venda em múltiplos produtos)
-- Granularidade: tenant_id × venda_id × produto_id
-- Refresh: incremental merge, lookback 1 dia
```

### Regras
- Grain documentado em comentário **no topo do `.sql`**
- Grain documentado em `description` do `schema.yml`
- **Mistura de grains é proibida** em uma única fact
- Mudança de grain = novo modelo + ADR

---

## Surrogate Keys (SKs)

### Geração

```sql
{{ dbt_utils.generate_surrogate_key(['tenant_id', 'cliente_id']) }} AS cliente_sk
```

### Composição
- **Sempre** inclui `tenant_id` na hash
- Ordem dos campos no array é importante (afeta hash)
- Convenção do projeto: `[tenant_id, natural_key_1, natural_key_2, ...]`

### Sufixo
- `_sk` para surrogate key
- `_id` para natural key

### Exemplo

```sql
-- dim_clientes
SELECT
  {{ dbt_utils.generate_surrogate_key(['tenant_id', 'cliente_id']) }} AS cliente_sk,
  tenant_id,
  cliente_id,             -- natural key (vem do source)
  nome_cliente,
  ...
FROM {{ ref('silver_dw_clientes') }}
```

```sql
-- fct_vendas (referenciando dim)
SELECT
  ...
  {{ dbt_utils.generate_surrogate_key(['v.tenant_id', 'v.cliente_id']) }} AS cliente_sk,
  v.dt_venda,
  v.vlr_total
FROM {{ ref('silver_dw_vendas') }} v
```

---

## Conformed Dimensions

`dim_clientes` é a **única** dimensão de cliente. Usada por:
- `fct_vendas`
- `fct_devolucao`
- `fct_titulo_financeiro`
- `controle_inadimplentes` (Platinum)

### Regras
- Não duplicar dim por contexto (ex: NÃO criar `dim_clientes_vendas`)
- Mudanças em dim conformed afetam todos os facts → discutir em PR
- ADR obrigatório para criação de nova dim conformed

---

## Star Schema — Estrutura

```
              dim_data
                 |
   dim_cliente —[fct_vendas]— dim_produto
                 |
              dim_vendedor
                 |
              dim_empresa
```

### Regras
- **Fact no centro**, dims ao redor (1 hop)
- **Sem snowflake** (dim → outra dim) exceto casos especiais com ADR
- **FKs em fact** apontam para dim_*_sk
- **Dim degenerada**: atributo de baixa cardinalidade pode ficar direto no fact

---

## SCD Strategies

### Tipo 1 (default neste projeto)
**Sobrescreve atributos**. Histórico não preservado.

```sql
{{
  config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['tenant_id', 'cliente_id']
  )
}}
```

### Tipo 2 (futuro, sob demanda)
**Mantém histórico** com `valid_from`, `valid_to`, `is_current`.

ADR obrigatório para implementar SCD2 (custo + complexidade).

---

## Métricas / Medidas

### Aditivas (somam ao longo de todas dims)
- `vlr_total`, `qtd_vendida`

### Semi-aditivas (somam por algumas dims, não por outras)
- `saldo_em_aberto` — soma por cliente, mas não por dia

### Não-aditivas (calculadas, não somam)
- `pct_margem`, `ticket_medio` — recalcular em consultas

### Convenção de nomes
- `vlr_*` para monetário
- `qtd_*` para contagem
- `pct_*` para percentual
- Sufixo `_total`, `_unitario`, `_medio`, `_acumulado`

---

## Late-Arriving Facts

Quando dim ainda não tem o registro do qual fact depende:

### Estratégia 1 — Inferred member
Inserir registro mínimo em dim com `is_inferred = TRUE` durante load do fact. Atualizar depois.

### Estratégia 2 — Default key
FK aponta para `cliente_sk = '00000000000000000000000000000000'` (registro "Desconhecido").

**Decidir caso a caso** + comentar no modelo.

---

## DRE Models — Padrão

Tabelas DRE são casos especiais (estrutura hierárquica + cálculos):

```sql
-- Modelo: dre_contabil
-- Grão: 1 linha = 1 conta DRE × período × tenant
-- Granularidade: tenant_id × conta_dre_id × ano_mes

WITH lancamentos AS (
  SELECT * FROM {{ ref('fct_lancamentos_origem') }}
),

estrutura AS (
  SELECT * FROM {{ ref('dim_estrutura_dre_contabil') }}
),

agregado AS (
  SELECT
    l.tenant_id,
    e.conta_dre_id,
    e.descricao_dre,
    DATE_TRUNC('month', l.dt_lancamento) AS ano_mes,
    SUM(l.vlr_lancamento) AS vlr_dre
  FROM lancamentos l
  JOIN estrutura e ON l.tenant_id = e.tenant_id AND l.conta_id = e.conta_id
  GROUP BY 1, 2, 3, 4
)

SELECT * FROM agregado
```

---

## Platinum Models

Visões de negócio prontas para consumo (BI, dashboards). Geralmente `view`:

```sql
{{ config(materialized='view') }}

SELECT
  d.ano_mes,
  d.descricao_dre,
  d.vlr_dre,
  o.vlr_orcado,
  d.vlr_dre - o.vlr_orcado AS vlr_variacao,
  CASE
    WHEN o.vlr_orcado > 0 THEN (d.vlr_dre - o.vlr_orcado) / o.vlr_orcado
    ELSE NULL
  END AS pct_variacao
FROM {{ ref('dre_contabil') }} d
LEFT JOIN {{ ref('orcamento_unit_01') }} o
  ON d.ano_mes = o.ano_mes AND d.descricao_dre = o.descricao_dre
WHERE d.tenant_id = 'unit_01'
```

---

## Anti-Patterns

- ❌ Fact sem `tenant_id`
- ❌ Fact sem `dt_*` (sem dim de tempo)
- ❌ Fact com múltiplos grains misturados
- ❌ FK em fact apontando para natural key (`cliente_id`) em vez de SK (`cliente_sk`)
- ❌ Dim duplicada por contexto (`dim_clientes_vendas`, `dim_clientes_titulos`)
- ❌ Snowflake sem ADR
- ❌ Métrica calculada armazenada em fact (calcular em camada de consumo)
- ❌ Hardcoded `tenant_id` em modelo (deve filtrar via partition no consumo)

---

## Documentação Obrigatória

Toda fact/dim em `schema.yml` tem:
- `description` em PT-BR explicando propósito
- `meta.layer` (silver/gold/platinum)
- `meta.owner` (vhmac)
- `meta.grain` (apenas em facts, ex: "tenant_id × venda_id × produto_id")
- Tests mínimos (PK not_null + unique, FKs relationships)

---

## Referências
- [Kimball Group — Dimensional Modeling Techniques](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/)
- [data-quality](data-quality.instructions.md) — testes Kimball
- [dbt](dbt.instructions.md) — implementação dbt
- [naming-conventions](naming-conventions.instructions.md) — nomes de tabelas/colunas
