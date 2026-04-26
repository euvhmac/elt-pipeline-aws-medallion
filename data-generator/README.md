# Data Generator

Gerador sintético multi-tenant que produz Parquets particionados em Hive layout. Substitui Airbyte/Fivetran sem expor dados reais.

## Quickstart

```bash
poetry install
poetry run python -m data_generator generate \
  --tenants unit_01,unit_02 \
  --datamarts comercial,financeiro \
  --date 2025-04-25 \
  --output ./data-generator/output \
  --seed 42
```

Validar:
```bash
poetry run python -m data_generator validate \
  --output ./data-generator/output \
  --date 2025-04-25
```

## Estrutura

```
data-generator/
├── src/data_generator/
│   ├── config.py          # tenants + volumes por tabela
│   ├── schemas.py         # PyArrow schemas (SSoT)
│   ├── generators.py      # Faker logic por tabela
│   ├── orchestrator.py    # ordem de geracao + refs FK
│   ├── writers.py         # Parquet local (S3 na Sprint 3)
│   ├── logging_utils.py   # logger JSON estruturado
│   └── cli.py             # entrypoint Click
├── tests/
└── output/                # gitignored
```

## Particionamento

```
output/<datamart>/<table>/tenant_id=<unit_NN>/year=YYYY/month=MM/day=DD/part-0000.snappy.parquet
```

## Volumes

23 tabelas × 5 tenants = **115 Parquets/dia** (volume default).

Use `--volume-multiplier 0.1` para smoke tests rápidos.

## Testes

```bash
poetry run pytest data-generator/tests -v
```
