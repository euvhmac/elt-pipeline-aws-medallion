---
applyTo: '**/*.py'
---

# Python Standards

> Padrões Python 3.11+ para data-generator, Airflow DAGs/utils e Lambda functions.

---

## Versão & Tooling

- **Python 3.11+** (sintaxe match-case, melhor performance, fastpath errors)
- **Package manager**: Poetry (`pyproject.toml`) ou `pip-tools` (`requirements.in`)
- **Linter**: `ruff` (regras: E, F, I, N, B, UP)
- **Formatter**: `black` com `--line-length 100`
- **Type checker**: `mypy --strict` em código compartilhado; opcional em scripts

---

## Type Hints — OBRIGATÓRIOS

**Toda função pública** tem type hints completos (params + return):

```python
# ✅ Correto
from decimal import Decimal
from datetime import datetime

def calcular_total(
    qtd: Decimal,
    vlr_unitario: Decimal,
    pct_desconto: Decimal = Decimal("0"),
) -> Decimal:
    """Calcula o valor total aplicando desconto percentual."""
    subtotal = qtd * vlr_unitario
    desconto = subtotal * pct_desconto
    return subtotal - desconto
```

```python
# ❌ Errado: sem type hints
def calcular_total(qtd, vlr_unitario, pct_desconto=0):
    return qtd * vlr_unitario * (1 - pct_desconto)
```

### Generics modernos (Python 3.9+)

```python
# ✅ Sintaxe nova
def listar_vendas() -> list[dict[str, Any]]:
    ...

# ❌ Sintaxe antiga (deprecated)
from typing import List, Dict
def listar_vendas() -> List[Dict[str, Any]]:
    ...
```

### Optional / Union

```python
# ✅ Python 3.10+
def buscar(id: str) -> dict | None:
    ...

# ⚠️ Aceitável (compat)
from typing import Optional
def buscar(id: str) -> Optional[dict]:
    ...
```

---

## Logging — Estruturado JSON

**NUNCA `print()`** em código de produção (exceto scripts standalone CLI).

### Pattern padrão

```python
import logging
import json
from datetime import datetime

logger = logging.getLogger(__name__)

# Configurar JSON formatter (boilerplate em utils/logging.py)
def log_with_context(level: str, message: str, **context) -> None:
    record = {
        "timestamp": datetime.utcnow().isoformat(),
        "level": level,
        "service": "data-generator",
        "message": message,
        **context,
    }
    print(json.dumps(record))  # stdout = CloudWatch Logs

# Uso
logger.info(
    "venda_gerada",
    extra={
        "tenant_id": "unit_01",
        "venda_id": "v-12345",
        "vlr_total": "1500.00",
    },
)
```

### Alternativa: `structlog`

```python
import structlog

logger = structlog.get_logger()
logger.info("venda_gerada", tenant_id="unit_01", vlr_total=1500.00)
```

### Campos obrigatórios em logs de produção
- `timestamp` (ISO 8601 UTC)
- `level` (DEBUG/INFO/WARNING/ERROR/CRITICAL)
- `service` (nome do componente)
- `message` (snake_case event, ex: `venda_gerada`, `upload_failed`)
- Contexto: `tenant_id`, `dag_id`, `task_id`, `request_id` quando aplicável

---

## Decimal para Dinheiro

**SEMPRE `Decimal`** para valores monetários:

```python
from decimal import Decimal

# ✅ Correto
vlr_total: Decimal = Decimal("1500.00")
vlr_unitario: Decimal = Decimal("12.345")

# ❌ NUNCA
vlr_total = 1500.00       # float, perde precisão
vlr_total = 1500          # int, sem decimais
```

### Conversão segura

```python
from decimal import Decimal

# String → Decimal (preferido)
v = Decimal("12.99")

# float → Decimal (cuidado: arredondamento)
v = Decimal(str(12.99))   # ✅ via string
v = Decimal(12.99)        # ❌ propaga imprecisão de float
```

---

## Error Handling — System Boundaries

**Validar nas fronteiras do sistema** (input do usuário, API externa, leitura de arquivo). **Não** em chamadas internas.

### ✅ Boundary validation

```python
def upload_to_s3(local_path: str, s3_uri: str) -> None:
    if not Path(local_path).exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {local_path}")
    if not s3_uri.startswith("s3://"):
        raise ValueError(f"URI inválida: {s3_uri}")

    s3.upload_file(local_path, ...)
```

### ❌ Defensive overkill

```python
def somar(a: int, b: int) -> int:
    if not isinstance(a, int):       # ❌ type hint já garante
        raise TypeError(...)
    if not isinstance(b, int):       # ❌ desnecessário
        raise TypeError(...)
    return a + b
```

### Re-raise pattern

```python
try:
    upload_to_s3(...)
except ClientError as e:
    logger.error(
        "s3_upload_failed",
        extra={"error": str(e), "bucket": bucket},
    )
    raise  # ✅ propaga após log
```

---

## Estrutura de Módulo

```
data-generator/
├── pyproject.toml
├── src/
│   └── data_generator/
│       ├── __init__.py
│       ├── main.py              ← entrypoint CLI
│       ├── config.py            ← settings (pydantic-settings ou dataclass)
│       ├── schemas/             ← schemas pyarrow por datamart
│       │   ├── __init__.py
│       │   ├── comercial.py
│       │   └── financeiro.py
│       ├── generators/          ← lógica Faker
│       │   ├── __init__.py
│       │   └── vendas.py
│       └── io/                  ← S3, parquet write
│           ├── __init__.py
│           └── s3_writer.py
└── tests/
    ├── __init__.py
    ├── unit/
    │   └── test_vendas.py
    └── integration/
        └── test_s3_writer.py
```

---

## Funções — Tamanho e Responsabilidade

- **Single Responsibility**: 1 função = 1 propósito
- **Tamanho ideal**: < 30 linhas (não regra estrita, mas sinal)
- **Args máximos**: 5 (acima disso, usar `dataclass` ou `@dataclass(frozen=True)`)

### ✅ Pequena e composta

```python
def gerar_vendas(tenant_id: str, dt: date, volume: int) -> list[Venda]:
    return [_gerar_venda(tenant_id, dt) for _ in range(volume)]

def _gerar_venda(tenant_id: str, dt: date) -> Venda:
    return Venda(
        tenant_id=tenant_id,
        venda_id=str(uuid4()),
        dt_venda=dt,
        vlr_total=fake_valor(),
    )
```

---

## Constants

```python
# constants.py ou no topo do módulo
from typing import Final

DEFAULT_VOLUME_PER_DAY: Final[int] = 1000
MAX_RETRIES: Final[int] = 3
TENANT_IDS: Final[tuple[str, ...]] = ("unit_01", "unit_02", "unit_03", "unit_04", "unit_05")
```

---

## Dataclasses & Pydantic

### Dataclasses para domínio interno

```python
from dataclasses import dataclass
from decimal import Decimal
from datetime import date

@dataclass(frozen=True, slots=True)
class Venda:
    tenant_id: str
    venda_id: str
    dt_venda: date
    vlr_total: Decimal
```

### Pydantic v2 para boundaries (API/config)

```python
from pydantic import BaseModel, Field
from decimal import Decimal

class VendaPayload(BaseModel):
    tenant_id: str = Field(pattern=r"^unit_0[1-5]$")
    vlr_total: Decimal = Field(ge=0)
```

---

## Globals — PROIBIDOS (Mutáveis)

```python
# ❌ Global mutável
_cache: dict = {}

def get(key: str):
    if key not in _cache:
        _cache[key] = compute(key)
    return _cache[key]
```

```python
# ✅ Funcional (functools.cache) ou explícito
from functools import lru_cache

@lru_cache(maxsize=128)
def get(key: str) -> Any:
    return compute(key)
```

```python
# ✅ Constants imutáveis OK
TENANT_IDS: Final[tuple[str, ...]] = (...)
```

---

## Imports

```python
# ✅ Ordem: stdlib → third-party → local
import json
import logging
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import boto3
import pyarrow as pa
from faker import Faker

from data_generator.schemas import comercial
from data_generator.io.s3_writer import write_parquet
```

Auto-organização via `ruff` (regra `I`).

### Anti-patterns
- ❌ `from module import *`
- ❌ Imports relativos sem necessidade (`from .utils import x` quando absoluto funciona)
- ❌ Imports dentro de função (exceto lazy/circular)

---

## Testing — Pytest

Detalhes em [testing.instructions.md](testing.instructions.md). Resumo:

- **Cobertura mínima**: 70% data-generator, 50% Airflow utils, 80% Lambda
- **Naming**: `test_<unit>_<scenario>_<expected>`
- **Mocking AWS**: `moto` library
- **Fixtures**: `conftest.py` por nível

```python
# tests/unit/test_vendas.py
import pytest
from datetime import date
from decimal import Decimal

from data_generator.generators.vendas import gerar_vendas

def test_gerar_vendas_quantidade_correta():
    vendas = gerar_vendas("unit_01", date(2024, 1, 1), volume=10)
    assert len(vendas) == 10

def test_gerar_vendas_tenant_correto():
    vendas = gerar_vendas("unit_03", date(2024, 1, 1), volume=5)
    assert all(v.tenant_id == "unit_03" for v in vendas)

def test_gerar_vendas_valor_decimal():
    vendas = gerar_vendas("unit_01", date(2024, 1, 1), volume=1)
    assert isinstance(vendas[0].vlr_total, Decimal)
```

---

## Async / Concurrency

- Preferir **paralelismo síncrono via `concurrent.futures`** para I/O em batch
- **`asyncio`** apenas quando há benefício claro (muitas conexões simultâneas)
- **Multiprocessing** apenas para CPU-bound (raro neste projeto)

```python
from concurrent.futures import ThreadPoolExecutor

def upload_all(files: list[Path]) -> None:
    with ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(upload_to_s3, files)
```

---

## Anti-Patterns Python

- ❌ `print()` em produção (usar logging)
- ❌ `float` para dinheiro
- ❌ `except Exception:` sem re-raise ou log específico
- ❌ Bare `except:` (captura SystemExit, KeyboardInterrupt)
- ❌ Globals mutáveis
- ❌ Funções públicas sem type hints
- ❌ Funções > 50 linhas (refatorar)
- ❌ Mutable default args (`def f(items=[])`)
- ❌ `from x import *`
- ❌ Comments óbvios (`# increment i` em `i += 1`)
- ❌ String concat em loops (usar `"".join(...)`)
- ❌ Path manipulation com strings (usar `pathlib.Path`)

---

## CI Gates

- `ruff check .` (lint)
- `ruff format --check .` (formato)
- `mypy src/` (types em código shared)
- `pytest --cov=src --cov-fail-under=70`
- `bandit -r src/` (security scan)

---

## Referências
- [PEP 8](https://peps.python.org/pep-0008/)
- [PEP 484 — Type Hints](https://peps.python.org/pep-0484/)
- [ruff rules](https://docs.astral.sh/ruff/rules/)
- [airflow](airflow.instructions.md) — DAGs específicas
- [testing](testing.instructions.md) — pytest detalhado
