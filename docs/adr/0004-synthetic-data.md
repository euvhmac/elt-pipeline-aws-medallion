# ADR-0004 — Gerador Sintético Python vs Airbyte vs Datasets Públicos

- **Status**: Accepted
- **Data**: 2025-04-25
- **Decisores**: Vhmac (autor)

---

## Contexto

A solução original utilizava **Airbyte (self-hosted em AKS)** para ingestão (EL) de múltiplos sistemas-fonte (~8 datamarts × 5 unidades). Para o portfólio público, expor dados reais é inviável (NDA, segurança). Opções:

1. **Gerador Python sintético** com Faker
2. **Airbyte open-source** com sources sintéticos (faker connector)
3. **Datasets públicos** (Kaggle, NYC Taxi, etc.)
4. **Snapshots redacted** dos dados originais

Critérios:
- Realismo (estruturalmente similar aos dados originais)
- Multi-tenancy (5 unit_ ids)
- Custo operacional
- Reprodutibilidade
- Segurança (zero leak de dados/lógica corporativa)
- Demonstração de skills (modelagem dimensional)

---

## Decisão

**Adotar gerador Python sintético customizado**, baseado em Faker + lógica de negócio determinística, produzindo Parquet particionado por tenant + data direto em S3.

---

## Justificativa

### Por que gerador sintético customizado é a melhor opção

1. **Controle total sobre estrutura**:
   - Schemas idênticos aos das tabelas Silver/Gold do dbt
   - Permite testar todos os edge cases (NULL, valores extremos, late-arriving)

2. **Multi-tenancy realista**:
   - 5 tenants (`unit_01`..`unit_05`)
   - Cada um com escala/distribuição ligeiramente diferente
   - Particionamento Hive em S3

3. **Reprodutibilidade**:
   - Seed fixa → mesmos dados sempre
   - Útil para tests de regressão dbt

4. **Custo zero**:
   - Roda em qualquer máquina
   - Sem Airbyte cloud ($300+/mês), sem servidor self-hosted, sem APIs externas

5. **Segurança máxima**:
   - 0% de relação com dados reais corporativos
   - Faker `pt_BR` produz CNPJs/nomes/endereços plausíveis mas falsos

6. **Demonstração de skills**:
   - Modelagem de domínio (8 datamarts ERP-like)
   - PyArrow + Parquet + particionamento
   - Geração coerente referencial (FKs entre tabelas)
   - Distribuições estatísticas realistas

### Limitações aceitas

1. **Não simula sistemas-fonte reais**:
   - Não testa connectors (REST APIs, JDBC, mainframe)
   - Mitigação: documentar em README que ingestão real requer Airbyte/Fivetran

2. **Distribuições aproximadas**:
   - Cardinalidades não batem 1:1 com dados originais
   - Mitigação: parametrizar volumes para aproximar

3. **Trabalho inicial**:
   - Definir schemas + geradores + coerência leva tempo
   - Mitigação: investimento único, paga em todas as iterações futuras

---

## Comparação Detalhada

| Critério | Gerador Custom | Airbyte Faker | Datasets Públicos | Snapshots Redacted |
|---|---|---|---|---|
| Custo | $0 | $0 (OSS) | $0 | $0 |
| Setup time | Médio (1-2 dias) | Médio (cluster Airbyte) | Baixo | Alto (anonimização) |
| Realismo do schema | ✅ Total controle | ⚠️ Schemas genéricos | ❌ Não bate | ✅ Idêntico |
| Multi-tenant | ✅ Built-in | ❌ Manual | ❌ N/A | ⚠️ Manual |
| Reprodutibilidade | ✅ Seed fixa | ⚠️ Aleatório | ✅ | ✅ |
| Segurança | ✅✅ Zero risk | ✅ Zero risk | ✅ | ⚠️ Risco de leak residual |
| Coerência referencial | ✅ Pool de IDs | ❌ Sem joins entre tabelas | ⚠️ Limitado | ✅ |
| Demonstra skills | ✅✅ Modelagem | ⚠️ Apenas usa Airbyte | ❌ | ⚠️ |

---

## Consequências

### Positivas

- ✅ Pipeline 100% reproduzível por terceiros
- ✅ Custo $0 de ingestão
- ✅ Zero risco de exposição de dados/lógica corporativa
- ✅ Schemas evoluídos junto com modelos dbt (single source of truth)
- ✅ Demonstra skills de modelagem dimensional + Python data engineering

### Negativas

- ⚠️ Não substitui experiência com Airbyte real (que era usada na solução original)
- ⚠️ Distribuições estatísticas podem desviar do original (mitigação: documentar)
- ⚠️ Manutenção: se schema dbt mudar, gerador precisa atualizar

### Mitigações

- Schemas centralizados em `data-generator/src/schemas/` referenciados em testes dbt
- CI valida que schema gerador bate com schema source dbt
- ADR documenta caminho de upgrade (Airbyte connectors)

---

## Alternativas Consideradas

### Alternativa 1: Airbyte open-source self-hosted
**Por que rejeitada**:
- Custo de hosting (~$30-100/mês mínimo)
- Setup complexo (PostgreSQL + Temporal + Airbyte stack)
- Sources Faker disponíveis mas com schemas genéricos (não ERP-like)
- Demonstra apenas "uso do Airbyte" — não modelagem

**Quando reconsiderar**: se o foco do projeto migrasse para "demonstrar EL com tools de mercado".

### Alternativa 2: Datasets Kaggle / NYC Taxi
**Por que rejeitada**:
- Sem multi-tenancy
- Schemas não simulam ERP corporativo
- Sem possibilidade de testar lógica DRE/Faturamento/Estoque

### Alternativa 3: Snapshots redacted da fonte original
**Por que rejeitada**:
- Risco residual de leak (anonimização imperfeita)
- Trabalho de anonimização > trabalho de gerador novo
- Limitação de NDA

### Alternativa 4: Mockaroo / Synthea (geradores cloud)
**Por que rejeitada**:
- Mockaroo: bom para tabelas simples, ruim para schemas referenciais
- Synthea: focado em dados de saúde, não corporativos
- Custo recorrente para tier alto

---

## Design do Gerador (Resumo)

Detalhes em [SOURCE_DATA_GENERATOR.md](../SOURCE_DATA_GENERATOR.md). Princípios:

1. **8 datamarts** modelando sistemas-fonte ERP-like:
   - comercial, financeiro, controladoria, logística, suprimentos, corporativo, industrial, contabilidade

2. **5 tenants** (`unit_01`..`unit_05`):
   - Volumes ligeiramente diferentes
   - Algumas tabelas exclusivas por tenant (simulando heterogeneidade real)

3. **Coerência referencial**:
   - Pool de IDs por tenant persistido entre runs (.pickle)
   - `vendas` referencia `cliente_id` que existe em `clientes`

4. **Particionamento Hive em S3**:
   - `s3://bronze/<datamart>/<tabela>/tenant_id=unit_01/year=2025/month=04/day=25/`

5. **Estratégia incremental**:
   - Dia 1: full load
   - Dia N+1: novos registros + ~5% updates em existentes (CDC simulado)

---

## Roadmap de Realismo

| Fase | Realismo |
|---|---|
| Sprint 1 | Gerador básico (1 distribuição uniforme) |
| Sprint 3 | Distribuições realistas (Poisson, log-normal para valores monetários) |
| Sprint 4 | Coerência cross-tabelas (FKs resolvem 100%) |
| Sprint 6 | Late-arriving facts (registros backfilled aleatórios) |
| Phase 2 | Streaming mode (Kinesis em vez de batch S3) |

---

## CI Validation

Gerador deve passar suite de testes:

```python
# data-generator/tests/test_coherence.py
def test_all_vendas_reference_existing_clients():
    vendas = read_parquet("output/comercial/vendas/")
    clientes = read_parquet("output/comercial/clientes/")
    assert set(vendas["cliente_id"]).issubset(set(clientes["cliente_id"]))

def test_volumes_within_expected_range():
    vendas = read_parquet("output/comercial/vendas/")
    assert 25_000 < len(vendas) < 35_000  # ±20% de 30k
```

---

## Referências

- [Faker Documentation](https://faker.readthedocs.io/)
- [PyArrow Parquet Writers](https://arrow.apache.org/docs/python/parquet.html)
- [Airbyte Faker Source](https://docs.airbyte.com/integrations/sources/faker)
- [Synthea](https://github.com/synthetichealth/synthea)

---

## Revisão

Reavaliar se:
- Foco do projeto mudar para "demonstrar EL platforms"
- Necessidade de testar SCDs reais (snapshots históricos)
- Stakeholders exigirem validação contra dados reais
