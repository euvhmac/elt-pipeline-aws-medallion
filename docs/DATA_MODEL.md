# Modelo de Dados — Star Schema Multi-Tenant

## Visão Geral

A camada Gold é modelada como **star schema clássico** (Kimball), com tabelas Fact no centro e Dimensions ao redor. A camada Platinum cria visões de negócio por unidade (DREs e controle de inadimplentes).

**Multi-tenant**: todas as tabelas têm coluna `tenant_id` (`unit_01`..`unit_05`) para filtrar/agregar por unidade de negócio.

**Totais**: 21 Silver · 18 Gold (9 dims + 7 facts + 2 DREs) · 6 Platinum = **45 modelos dbt**

---

## Camada Gold — Star Schema

### Dimensions (9)

| Tabela | Descrição | PK |
|---|---|---|
| `dim_calendrio` | Calendário (datas, anos, meses, semanas, trimestres) | `data_id` |
| `dim_clientes` | Clientes (PJ + PF) com hierarquia geográfica | `cliente_sk` |
| `dim_produtos` | Produtos (família, grupo, marca, embalagem) | `produto_sk` |
| `dim_vendedores` | Vendedores com hierarquia regional | `vendedor_sk` |
| `dim_fornecedores` | Fornecedores por tenant | `fornecedor_sk` |
| `dim_empresas` | Empresas/filiais por tenant | `empresa_sk` |
| `dim_funcionarios` | Colaboradores por empresa | `funcionario_sk` |
| `dim_centros_custos` | Centros de custo contábil | `centro_custo_sk` |
| `dim_plano_contas` | Plano de contas (natureza, tipo) | `plano_conta_sk` |

### Facts (7)

| Tabela | Grão | Métricas principais | FKs |
|---|---|---|---|
| `fct_vendas` | 1 linha = 1 item de pedido | `vlr_unitario`, `vlr_total`, `qtd_vendida` | `cliente_sk`, `produto_sk`, `vendedor_sk`, `empresa_sk`, `data_id` |
| `fct_ordens_compra` | 1 linha = 1 item de OC | `vlr_unitario`, `vlr_total`, `qtd_solicitada` | `fornecedor_sk`, `empresa_sk`, `data_id` |
| `fct_ordens_producao` | 1 linha = 1 ordem de produção | `qtd_planejada`, `qtd_produzida`, `vlr_custo` | `empresa_sk`, `data_id` |
| `fct_expedicao` | 1 linha = 1 entrega | `vlr_frete`, `qtd_volumes`, `nr_dias_entrega` | `empresa_sk`, `data_id` |
| `fct_orcamento_projetos` | 1 linha = 1 projeto-mês | `vlr_orcado`, `vlr_realizado`, `vlr_delta` | `centro_custo_sk`, `empresa_sk`, `data_id` |
| `fct_titulo_financeiro` | 1 linha = 1 título financeiro | `vlr_titulo`, `vlr_pago`, `nr_dias_atraso`, `ds_situacao_titulo` | `empresa_sk`, `data_id` |
| `fct_lancamentos` | 1 linha = 1 lançamento contábil | `vlr_lancamento`, `vlr_final` (±DEBITO/CREDITO) | `plano_conta_sk`, `centro_custo_sk`, `empresa_sk`, `data_id` |

### Analytics / DRE (2)

| Tabela | Descrição |
|---|---|
| `dre_contabil` | DRE Contábil consolidado — agrega `fct_lancamentos` por empresa, centro de custo, tipo de conta e competência |
| `dre_gerencial` | DRE Gerencial — reclassifica `dre_contabil` em categorias de gestão (RECEITA_BRUTA, DESPESA_OPERACIONAL, ATIVO_CIRCULANTE, etc.) |

---

## Diagrama Star Schema (simplificado)

```
                        ┌──────────────────┐
                        │  dim_calendrio   │
                        └────────┬─────────┘
                                 │
  ┌──────────────────┐           │           ┌──────────────────┐
  │   dim_clientes   │           │           │   dim_produtos   │
  └────────┬─────────┘           │           └────────┬─────────┘
           │           ┌─────────┴──────────┐          │
           └──────────►│    fct_vendas      │◄─────────┘
                       │ (grão: 1 item OC)  │
           ┌──────────►│                    │◄─────────┐
           │           └────────────────────┘          │
           │                                           │
  ┌────────┴──────┐                          ┌─────────┴──────────┐
  │ dim_vendedores│                          │    dim_empresas    │
  └───────────────┘                          └────────────────────┘
```

---

## Camada Platinum — Visões de Negócio

| Modelo | Derivado de | Descrição |
|---|---|---|
| `controle_inadimplentes` | `fct_titulo_financeiro` | Títulos com `ds_situacao_titulo = 'VENCIDO'` — inadimplência por empresa |
| `dre_contabil_unit_01` | `dre_contabil` | DRE Contábil filtrado para `tenant_id = 'unit_01'` |
| `dre_contabil_unit_02` | `dre_contabil` | DRE Contábil filtrado para `tenant_id = 'unit_02'` |
| `dre_gerencial_unit_01` | `dre_gerencial` | DRE Gerencial filtrado para `tenant_id = 'unit_01'` |
| `dre_gerencial_unit_02` | `dre_gerencial` | DRE Gerencial filtrado para `tenant_id = 'unit_02'` |
| `dim_produtos_otimizada` | `dim_produtos` | Subconjunto de colunas para consultas de catálogo |

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
- Glue table com partition projection (23 tabelas externas)

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
