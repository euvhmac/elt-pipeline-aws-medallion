---
applyTo: '**/{tests,test}/**'
---

# Testing — Pirâmide

> Padrões de testes para Python (pytest), dbt (schema/singular), Airflow (DagBag) e Terraform (validation).

---

## Pirâmide de Testes

```
                    ╱╲
                   ╱E2E╲                  ← poucos, end-to-end (Sprint 7)
                  ╱──────╲
                 ╱integration╲             ← integração com AWS (moto)
                ╱─────────────╲
               ╱     unit      ╲           ← maioria, rápidos, isolados
              ╱──────────────────╲
```

---

## Cobertura Mínima por Componente

| Componente | Cobertura | Tooling |
|---|---|---|
| `data-generator/src/` | **70%** | `pytest --cov` |
| `airflow/dags/utils/` | **50%** | `pytest --cov` |
| `lambda/*/handler.py` | **80%** | `pytest --cov` |
| `dbt/models/gold/` | 100% PKs/FKs | `dbt test` |
| `dbt/models/silver/` | mínimo schema tests | `dbt test` |
| `infra/modules/` | `terraform validate` + `tflint` + `tfsec` | CI |

---

## Pytest — Convenções

### Naming

```
test_<unit>_<scenario>_<expected>
```

**Exemplos**:
```python
def test_gerar_vendas_quantidade_correta():
    ...

def test_gerar_vendas_tenant_invalido_levanta_erro():
    ...

def test_upload_to_s3_bucket_inexistente_falha_com_client_error():
    ...
```

### Estrutura AAA

```python
def test_calcular_total_com_desconto():
    # Arrange
    qtd = Decimal("10")
    vlr_unitario = Decimal("100.00")
    pct_desconto = Decimal("0.10")

    # Act
    resultado = calcular_total(qtd, vlr_unitario, pct_desconto)

    # Assert
    assert resultado == Decimal("900.00")
```

### Pasta

```
tests/
├── __init__.py
├── conftest.py              ← fixtures globais
├── unit/
│   ├── __init__.py
│   ├── test_vendas.py
│   ├── test_clientes.py
│   └── conftest.py          ← fixtures de unit
├── integration/
│   ├── __init__.py
│   ├── test_s3_writer.py    ← usa moto
│   └── conftest.py
└── e2e/                     ← Sprint 7
    └── test_pipeline_full.py
```

---

## Fixtures — `conftest.py`

```python
# tests/conftest.py
import pytest
from datetime import date
from decimal import Decimal

from data_generator.schemas.comercial import Venda


@pytest.fixture
def sample_venda() -> Venda:
    return Venda(
        tenant_id="unit_01",
        venda_id="v-12345",
        dt_venda=date(2024, 1, 15),
        vlr_total=Decimal("1500.00"),
    )


@pytest.fixture
def tenant_ids() -> list[str]:
    return ["unit_01", "unit_02", "unit_03", "unit_04", "unit_05"]
```

---

## Mocking AWS — `moto`

```python
# tests/integration/test_s3_writer.py
import boto3
import pytest
from moto import mock_aws

from data_generator.io.s3_writer import write_parquet


@mock_aws
def test_write_parquet_to_s3():
    # Arrange
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="test-bronze")

    # Act
    write_parquet(
        records=[{"tenant_id": "unit_01", "vlr_total": "1500.00"}],
        s3_uri="s3://test-bronze/comercial/vendas.parquet",
    )

    # Assert
    response = s3.list_objects_v2(Bucket="test-bronze")
    assert response["KeyCount"] == 1
    assert response["Contents"][0]["Key"] == "comercial/vendas.parquet"
```

### Setup `moto`

```toml
# pyproject.toml
[tool.poetry.group.dev.dependencies]
moto = {version = "^5.0", extras = ["s3", "sns", "lambda", "secretsmanager"]}
```

---

## Test Data — Pequeno e Determinístico

### ✅ Bom

```python
def test_gerar_vendas_volume_pequeno():
    vendas = gerar_vendas("unit_01", date(2024, 1, 1), volume=3)
    assert len(vendas) == 3
```

### ❌ Ruim

```python
def test_gerar_vendas():
    vendas = gerar_vendas("unit_01", date(2024, 1, 1), volume=10000)  # ❌ lento
    assert len(vendas) == 10000
```

### Faker com seed

```python
from faker import Faker

@pytest.fixture
def fake() -> Faker:
    f = Faker(locale="pt_BR")
    Faker.seed(42)  # ✅ determinístico
    return f
```

---

## Parametrização

```python
import pytest

@pytest.mark.parametrize("tenant_id", ["unit_01", "unit_02", "unit_03", "unit_04", "unit_05"])
def test_gerar_vendas_para_cada_tenant(tenant_id):
    vendas = gerar_vendas(tenant_id, date(2024, 1, 1), volume=5)
    assert all(v.tenant_id == tenant_id for v in vendas)


@pytest.mark.parametrize("tenant_invalido", ["unit_06", "unit_99", "UNIT_01", "", None])
def test_gerar_vendas_tenant_invalido_levanta_erro(tenant_invalido):
    with pytest.raises(ValueError, match="tenant"):
        gerar_vendas(tenant_invalido, date(2024, 1, 1), volume=5)
```

---

## dbt Tests

### Schema tests (em `schema.yml`)

Detalhes em [data-quality](data-quality.instructions.md). Resumo: 100% de PKs+FKs em Gold.

### Singular tests (`dbt/tests/`)

```sql
-- dbt/tests/test_no_negative_revenue.sql
-- Verifica que receita líquida não é negativa em DRE
SELECT
  tenant_id,
  ano_mes,
  vlr_dre
FROM {{ ref('dre_contabil') }}
WHERE descricao_dre = 'Receita Liquida'
  AND vlr_dre < 0
```

### CI gate

```bash
# CI runs
dbt build --select state:modified+ --defer --state ./manifest-prod
dbt test --severity error                  # bloqueio
dbt test --severity warn || true           # apenas warning
```

---

## Airflow DagBag Test

```python
# tests/dags/test_dagbag.py
import pytest
from airflow.models import DagBag


@pytest.fixture(scope="session")
def dagbag():
    return DagBag(dag_folder="airflow/dags", include_examples=False)


def test_no_import_errors(dagbag):
    assert dagbag.import_errors == {}, f"Import errors: {dagbag.import_errors}"


def test_all_dags_have_tags(dagbag):
    for dag_id, dag in dagbag.dags.items():
        assert dag.tags, f"DAG {dag_id} sem tags"


def test_all_dags_have_failure_callback(dagbag):
    for dag_id, dag in dagbag.dags.items():
        assert (
            dag.default_args.get("on_failure_callback") is not None
        ), f"DAG {dag_id} sem on_failure_callback"


def test_all_dags_have_owner_vhmac(dagbag):
    for dag_id, dag in dagbag.dags.items():
        assert dag.default_args.get("owner") == "vhmac"
```

---

## Terraform Tests

### `terraform validate` (sintaxe)

```bash
terraform -chdir=infra/envs/dev validate
```

### `tflint` (linting + best practices)

```bash
tflint --init
tflint --recursive infra/
```

### `tfsec` (security)

```bash
tfsec infra/
```

### Terratest (futuro, Phase 2)

Tests em Go que provisionam infra real e validam outputs. Custo + complexidade — adiar.

---

## Coverage Reports

```bash
# Local
pytest --cov=src --cov-report=html --cov-report=term-missing

# CI
pytest --cov=src --cov-fail-under=70 --cov-report=xml
```

`pyproject.toml`:

```toml
[tool.coverage.run]
source = ["src"]
omit = ["tests/*", "**/__init__.py"]

[tool.coverage.report]
fail_under = 70
exclude_lines = [
    "pragma: no cover",
    "raise NotImplementedError",
    "if __name__ == .__main__.:",
]
```

---

## Marks Customizados

```python
# pyproject.toml
[tool.pytest.ini_options]
markers = [
    "slow: testes que demoram > 1s",
    "integration: testes que fazem chamadas externas",
    "e2e: testes end-to-end (lentos)",
]
```

```python
@pytest.mark.slow
def test_processo_grande():
    ...

@pytest.mark.integration
@mock_aws
def test_s3_real():
    ...
```

```bash
pytest -m "not slow"            # skip lentos
pytest -m "integration"         # só integração
```

---

## CI Gates Obrigatórios

Todo PR deve passar:

```yaml
- pytest --cov=src --cov-fail-under=70   # Python
- dbt test --severity error              # dbt schema
- dbt source freshness                   # source freshness
- terraform validate                     # TF syntax
- tflint --recursive                     # TF best practices
- tfsec                                  # TF security
- bandit -r src/ -ll                     # Python security
- pip-audit                              # CVEs
```

---

## Anti-Patterns Testing

- ❌ Tests sem assertions (`def test_x(): foo()`)
- ❌ Mocking demais (testa o mock, não a unidade)
- ❌ Test data > 1000 registros (lento)
- ❌ Test depende de outro (use fixtures)
- ❌ Test depende de ordem (`pytest --random-order` deve passar)
- ❌ Sleep/timing-dependent (flaky)
- ❌ Sem cleanup (lixo entre runs)
- ❌ Faker sem seed (não-determinístico)
- ❌ Skipping flaky tests sem fix issue criada
- ❌ Cobertura artificial (testar getter/setter triviais)

---

## Test Doubles — Quando Usar

| Tipo | Quando |
|---|---|
| **Stub** | Resposta canned (sem lógica) |
| **Mock** | Validar chamadas (verify call) |
| **Fake** | Implementação simplificada (in-memory DB) |
| **Spy** | Mock + chamada real |

```python
from unittest.mock import patch, MagicMock

@patch("data_generator.io.s3_writer.boto3.client")
def test_upload_chama_s3_put_object(mock_boto):
    mock_s3 = MagicMock()
    mock_boto.return_value = mock_s3

    upload_to_s3("local.parquet", "s3://bucket/key")

    mock_s3.upload_file.assert_called_once_with("local.parquet", "bucket", "key")
```

---

## Referências
- [pytest docs](https://docs.pytest.org/)
- [moto](https://docs.getmoto.org/)
- [data-quality](data-quality.instructions.md) — dbt tests
- [python](python.instructions.md) — type hints, structure
- [airflow](airflow.instructions.md) — DAG tests
