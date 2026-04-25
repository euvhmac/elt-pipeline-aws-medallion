# Gerador de Dados Sintéticos

Substitui o componente Airbyte original por um gerador Python que produz dados realistas em Parquet, particionados por tenant + data, prontos para upload S3.

## Por Que Sintético?

Veja [adr/0004-synthetic-data.md](adr/0004-synthetic-data.md) para decisão completa. Resumo:
- Reproduz comportamento do Airbyte (incremental + bulk) sem expor dados reais
- Permite controle determinístico (seed fixa) para testes
- Zero custo (sem Airbyte cloud, sem Fivetran)
- Demonstra conhecimento de modelagem dimensional

---

## Arquitetura

```
┌─────────────────────────────────────────────┐
│  data-generator/                            │
│  ├── pyproject.toml                         │
│  ├── src/                                   │
│  │   ├── schemas/        (PyArrow schemas)  │
│  │   ├── generators/     (Faker logic)      │
│  │   ├── writers/        (Parquet + S3)     │
│  │   ├── config.py       (datamarts, tenants│
│  │   └── main.py         (CLI entrypoint)   │
│  └── tests/                                 │
└─────────────────────────────────────────────┘
                    │
                    ▼
        ┌──────────────────────┐
        │  Local: ./output/    │  (dev mode)
        │  ou                  │
        │  S3: bronze bucket   │  (prd mode)
        └──────────────────────┘
```

---

## 8 Datamarts Sintéticos

Cada datamart simula um sistema-fonte ERP/operacional, com 5-10 tabelas:

| Datamart | Tabelas geradas | Volume diário/tenant |
|---|---|---|
| **comercial** | clientes, vendedores, pedidos, itens_pedido, vendas | ~30k linhas |
| **financeiro** | titulos_pagar, titulos_receber, baixas, condpag | ~20k linhas |
| **controladoria** | centros_custos, projetos, orcamento, realizado | ~5k linhas |
| **logistica** | filiais, transportadoras, expedicao, devolucao | ~10k linhas |
| **suprimentos** | fornecedores, ordens_compra, recebimento_mercadoria | ~8k linhas |
| **corporativo** | empresas, funcionarios, departamentos | ~1k linhas |
| **industrial** | produtos, materias_primas, ordens_producao | ~15k linhas |
| **contabilidade** | plano_contas, lancamentos, conciliacoes | ~25k linhas |

Total: ~110k linhas/tenant/dia × 5 tenants = **~550k linhas/dia**.

---

## Particionamento Hive

Estrutura de saída em S3:

```
s3://elt-pipeline-bronze-${env}/
└── comercial/
    └── vendas/
        ├── tenant_id=unit_01/
        │   └── year=2025/month=04/day=25/
        │       └── part-0000.snappy.parquet
        ├── tenant_id=unit_02/
        │   └── year=2025/month=04/day=25/
        │       └── part-0000.snappy.parquet
        └── ...
```

Vantagens:
- Athena partition projection elimina necessidade de `MSCK REPAIR`
- Predicate pushdown: `WHERE tenant_id='unit_01' AND year=2025` pula 80% dos arquivos
- Compatível com Iceberg hidden partitioning na camada Silver

---

## Schemas (PyArrow)

Schemas declarados centralmente em `src/schemas/` para garantir consistência:

```python
# src/schemas/comercial.py
import pyarrow as pa

VENDAS_SCHEMA = pa.schema([
    ("venda_id", pa.string()),
    ("data_venda", pa.timestamp("us")),
    ("cliente_id", pa.string()),
    ("vendedor_id", pa.string()),
    ("produto_id", pa.string()),
    ("empresa_id", pa.string()),
    ("quantidade", pa.decimal128(18, 4)),
    ("valor_unitario", pa.decimal128(18, 2)),
    ("valor_total", pa.decimal128(18, 2)),
    ("desconto_percentual", pa.decimal128(5, 2)),
    ("status", pa.string()),
    ("created_at", pa.timestamp("us")),
    ("updated_at", pa.timestamp("us")),
])
```

---

## Geradores Faker

Cada gerador encapsula lógica de negócio + aleatoriedade controlada:

```python
# src/generators/vendas.py
from faker import Faker
import random
from decimal import Decimal

fake = Faker("pt_BR")

def generate_venda(tenant_id: str, date: datetime) -> dict:
    quantidade = Decimal(random.randint(1, 100))
    valor_unit = Decimal(f"{random.uniform(10, 1000):.2f}")
    desconto = Decimal(f"{random.uniform(0, 20):.2f}")
    
    valor_total = quantidade * valor_unit * (1 - desconto / 100)
    
    return {
        "venda_id": fake.uuid4(),
        "data_venda": date,
        "cliente_id": f"CLI-{tenant_id}-{random.randint(1, 5000):05d}",
        "vendedor_id": f"VEND-{tenant_id}-{random.randint(1, 50):03d}",
        "produto_id": f"PRD-{tenant_id}-{random.randint(1, 1000):04d}",
        "empresa_id": f"EMP-{tenant_id}",
        "quantidade": quantidade,
        "valor_unitario": valor_unit,
        "valor_total": valor_total.quantize(Decimal("0.01")),
        "desconto_percentual": desconto,
        "status": random.choices(
            ["FATURADA", "PENDENTE", "CANCELADA"],
            weights=[80, 15, 5],
        )[0],
        "created_at": date,
        "updated_at": date,
    }
```

**Princípios**:
- IDs determinísticos por tenant (referenciáveis entre tabelas)
- Distribuições realistas (80% FATURADA, 15% PENDENTE...)
- Locale `pt_BR` para nomes/endereços/CNPJs

---

## Coerência Multi-Tabela

Para que joins funcionem nas camadas Silver/Gold, IDs precisam ser **referenciais**:

1. **Geração ordenada**: dimensões antes de fatos
   - `clientes` → `vendas` (vendas referencia cliente_id existente)
   - `produtos` → `vendas`
   - `vendedores` → `vendas`

2. **Pool de IDs por tenant**: cada gerador mantém um pool em memória:
   ```python
   pools = {
       "clientes": [generate_cliente_id() for _ in range(5000)],
       "produtos": [generate_produto_id() for _ in range(1000)],
   }
   # Vendas usa: random.choice(pools["clientes"])
   ```

3. **Persistência entre runs**: pool serializado em `.pickle` para que dia 2 referencie dia 1.

---

## Estratégia Incremental

Simulando comportamento do Airbyte CDC:

- **Dia N**: gera novos registros (e.g., 30k vendas novas)
- **Dia N+1**: gera novos registros + ~5% de updates em registros existentes (mudança de `status`, `updated_at`)
- Coluna `updated_at` permite captura incremental no dbt

```python
# Gerar updates
existing_vendas = read_parquet(f"s3://...vendas/tenant={t}/year={y}/month={m}/day={d-1}/")
updates = sample_pct(existing_vendas, pct=5)
for venda in updates:
    venda["status"] = random.choice(["FATURADA", "CANCELADA"])
    venda["updated_at"] = today
```

---

## CLI

```bash
poetry run python -m data_generator \
  --tenants unit_01,unit_02,unit_03,unit_04,unit_05 \
  --datamarts all \
  --date 2025-04-25 \
  --output s3://elt-pipeline-bronze-dev \
  --seed 42
```

Flags:
- `--tenants`: subset (default: todos)
- `--datamarts`: subset ou `all`
- `--date`: data lógica (default: hoje)
- `--output`: `local://./output` ou `s3://bucket`
- `--seed`: reprodutibilidade
- `--volume-multiplier`: 0.1 a 10x (default 1.0)

---

## Validação

Após gerar, validar consistência:

```bash
poetry run python -m data_generator validate \
  --output s3://elt-pipeline-bronze-dev \
  --date 2025-04-25
```

Validações:
- Todos os 8 × 5 = 40 caminhos têm pelo menos 1 arquivo
- Schemas batem com PyArrow declarado
- FKs resolvem (ex: 100% dos `cliente_id` em vendas existem em clientes)
- Counts dentro de faixas esperadas (±20% do volume médio)

---

## Volume e Custo

| Item | Valor |
|---|---|
| Linhas/dia (total) | ~550k |
| Arquivos Parquet/dia | 40 (1 por datamart-tabela-tenant) |
| Tamanho médio/arquivo | ~5-15 MB (Snappy) |
| Tamanho total/dia | ~150 MB |
| Tamanho/mês | ~4.5 GB |
| **Custo S3 PUT/mês** | <$0.05 |
| **Custo S3 storage/mês** | <$0.10 |

---

## Roadmap do Gerador

- **Sprint 1**: Versão local (output em `./output/`)
- **Sprint 3**: Upload S3 + DAG Airflow
- **Sprint 4+**: Fine-tuning de distribuições com base no que dbt models esperam
- **Phase 2**: Streaming mode (Kinesis em vez de batch S3)
