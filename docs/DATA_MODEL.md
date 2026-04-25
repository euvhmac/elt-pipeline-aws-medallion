# Modelo de Dados — Star Schema Multi-Tenant

## Visão Geral

A camada Gold é modelada como **star schema clássico** (Kimball), com tabelas Fact no centro e Dimensions ao redor. A camada Platinum derivada cria visões de negócio por unidade (DREs, controle de inadimplentes).

**Multi-tenant**: todas as tabelas têm coluna `tenant_id` (`unit_01`..`unit_05`) para filtrar/agregar por unidade de negócio.

---

## Camada Gold — Star Schema

### Dimensions (8)

| Tabela | Descrição | PK |
|---|---|---|
| `dim_calendrio` | Calendário (datas, anos, meses, semanas, trimestres) | `data_id` |
| `dim_clientes` | Clientes (PJ + PF) com hierarquia geográfica | `cliente_sk` |
| `dim_produtos` | Produtos (família, grupo, marca, embalagem) | `produto_sk` |
| `dim_empresas` | Empresas/filiais por tenant | `empresa_sk` |
| `dim_centros_custos` | Centros de custo contábil | `cc_sk` |
| `dim_contas_contabeis` | Plano de contas | `conta_sk` |
| `dim_condpag` | Condições de pagamento | `condpag_sk` |
| `dim_vendedor` | Vendedores | `vendedor_sk` |
| `dim_estrutura_dre_contabil` | Estrutura DRE (linhas e níveis) | `estrutura_dre_sk` |

### Facts (6)

| Tabela | Grão | Métricas principais | FKs |
|---|---|---|---|
| `fct_vendas` | 1 linha = 1 item de pedido | quantidade, valor_unit, valor_total, desconto | `cliente_sk`, `produto_sk`, `vendedor_sk`, `empresa_sk`, `data_id` |
| `fct_faturamento` | 1 linha = 1 item de NF | valor_faturado, base_icms, valor_imposto | `cliente_sk`, `produto_sk`, `empresa_sk`, `data_id` |
| `fct_devolucao` | 1 linha = 1 devolução | quantidade_devolvida, valor_devolucao, motivo | `cliente_sk`, `produto_sk`, `empresa_sk`, `data_id` |
| `fct_titulo_financeiro` | 1 linha = 1 título a pagar/receber | valor_titulo, valor_pago, dias_atraso | `cliente_sk`, `condpag_sk`, `empresa_sk`, `data_id` |
| `fct_lancamentos_origem` | 1 linha = 1 lançamento contábil | valor_lancamento, tipo (D/C) | `conta_sk`, `cc_sk`, `empresa_sk`, `data_id` |
| `fct_projetos_consolidados` | 1 linha = 1 projeto-mês | orçado, realizado, variação | `cc_sk`, `empresa_sk`, `data_id` |

### DRE (2)

| Tabela | Descrição |
|---|---|
| `dre_contabil` | DRE Contábil consolidado (resultado por linha de estrutura DRE) |
| `dre_gerencial` | DRE Gerencial (visão de gestão, com ajustes e reclassificações) |

---

## Diagrama Star Schema (simplificado)

```
                        ┌──────────────────┐
                        │   dim_calendrio  │
                        └────────┬─────────┘
                                 │
       ┌──────────────────┐      │       ┌──────────────────┐
       │  dim_clientes    │      │       │   dim_produtos   │
       └────────┬─────────┘      │       └────────┬─────────┘
                │                │                │
                │     ┌──────────┴───────────┐    │
                └────►│                      │◄───┘
                      │     fct_vendas       │
                      │                      │
       ┌────────────► │                      │ ◄────────────┐
       │              └──────────────────────┘              │
       │                                                    │
┌──────┴───────┐                                    ┌───────┴────────┐
│ dim_vendedor │                                    │  dim_empresas  │
└──────────────┘                                    └────────────────┘
```

---

## Camada Platinum — Visões de Negócio

### DREs por Unidade (5 modelos consolidados)

Cada unidade de negócio (`unit_01`..`unit_05`) tem seu próprio DRE Contábil e Gerencial filtrados:

| Modelo | Descrição |
|---|---|
| `dre_contabil_unit_01` | DRE Contábil Unidade 01 |
| `dre_contabil_unit_02` | DRE Contábil Unidade 02 |
| `dre_gerencial_unit_01` | DRE Gerencial Unidade 01 |
| `dre_gerencial_unit_02` | DRE Gerencial Unidade 02 |
| `dim_estrutura_dre_contabil_unit_01` | Estrutura DRE específica Unidade 01 |
| `dim_estrutura_dre_contabil_unit_02` | Estrutura DRE específica Unidade 02 |

### Outras Visões

| Modelo | Descrição |
|---|---|
| `controle_inadimplentes` | Títulos vencidos > 30 dias agregados por cliente/empresa |
| `dim_produtos_otimizada` | Dimensão de produtos enriquecida com classificação fiscal |

---

## Convenções de Nomenclatura

### Tabelas
- `silver_dw_<entidade>` — Silver
- `dim_<entidade>` — Dimensions Gold
- `fct_<evento>` — Facts Gold
- `dre_*` — DRE Gold/Platinum
- `<modelo>_unit_NN` — Platinum por unidade

### Colunas
- `<entidade>_id` — Natural key vinda do source
- `<entidade>_sk` — Surrogate key (gerada via `dbt_utils.generate_surrogate_key`)
- `dt_<evento>` — Timestamp/date
- `vlr_<conceito>` — Valores monetários (DECIMAL(18,2))
- `qtd_<conceito>` — Quantidades (DECIMAL/INTEGER)
- `tenant_id` — Identificador da unidade de negócio
- `_dbt_loaded_at` — Audit column injetada pelo dbt

---

## Multi-Tenancy: Estratégia

### Bronze
- Particionamento por `tenant_id` em S3
- Path: `s3://...-bronze-${env}/<datamart>/<tabela>/tenant_id=unit_NN/year=.../month=.../day=.../*.parquet`
- Glue table com partition projection

### Silver
- UNION dos 5 tenants em modelo unificado
- Coluna `tenant_id` preservada
- Padronização de schemas (alguns tenants tinham campos diferentes — coalesce)

### Gold
- Mesmo padrão Silver: tabela única com `tenant_id`
- Surrogate keys consideram `tenant_id` na composição

### Platinum
- Filtragem por `tenant_id`: cada unit tem suas views

---

## Surrogate Keys

Todas as dimensions usam surrogate keys geradas via `dbt_utils.generate_surrogate_key`:

```sql
{{ dbt_utils.generate_surrogate_key([
    'tenant_id',
    'cliente_id'
]) }} AS cliente_sk
```

Vantagens:
- Independência de natural keys (que podem mudar)
- Suporte a SCD Type 2 futuro
- Hash determinístico (re-runs produzem mesma SK)

---

## Testes de Qualidade Por Camada

### Silver
- `not_null` em PKs
- `unique` em chaves de negócio
- Schema validation via `dbt_expectations.expect_table_columns_to_match_set`

### Gold
- `not_null` + `unique` em todas as SKs
- `relationships` entre Facts e Dims
- `accepted_values` em colunas categóricas (status, tipo)
- Range tests via `dbt_expectations.expect_column_values_to_be_between`

### Platinum
- Singular tests: validação de balanços DRE (débitos = créditos)
- `expect_table_row_count_to_be_between` para detectar truncamentos

---

## Volumetria Estimada (após geração sintética diária)

| Camada | Tabelas | Linhas/dia (total) | Tamanho/dia |
|---|---|---|---|
| Bronze | 40 | ~500k | ~150 MB |
| Silver | 30 | ~400k | ~80 MB |
| Gold | 16 | ~150k | ~40 MB |
| Platinum | 9 | ~50k | ~10 MB |

Volume cumulativo após 90 dias: ~25 GB total (todas as camadas, todos os tenants).

---

## Lineage (Alto Nível)

```
[8 datamarts × 5 tenants = 40 fontes Bronze]
                    │
                    ▼
[30 modelos Silver — dw_* unificados]
                    │
        ┌───────────┼───────────┐
        ▼           ▼           ▼
[8 dims]    [6 facts]    [2 DREs Gold]
        │           │           │
        └───────────┼───────────┘
                    ▼
[9 modelos Platinum — visões por unidade]
                    │
                    ▼
              Consumo BI
```

Lineage detalhado disponível em `dbt docs serve` após Sprint 4.
