---
applyTo: 'airflow/dags/**/*.py'
---

# Airflow DAGs

> Padrões para Apache Airflow 2.9 rodando em Docker Compose local. Aplicável a `airflow/dags/**`.

---

## Stack

- **Airflow 2.9+** com TaskFlow API
- **Executor**: LocalExecutor (Docker Compose)
- **Database**: PostgreSQL 14 (metadata) + Redis (queue, futuro CeleryExecutor)
- **Conexões AWS**: via `airflow_settings.yaml` (Astronomer-style) ou env vars

---

## Estrutura de Pastas

```
airflow/
├── dags/
│   ├── dag_synthetic_source.py
│   ├── dag_dbt_aws_detailed.py
│   └── utils/
│       ├── __init__.py
│       ├── callbacks.py          ← on_failure_callback
│       ├── slack.py              ← Slack notifications
│       ├── dbt_helpers.py        ← dbt task generators
│       └── athena_helpers.py     ← Athena utilities
├── plugins/                      ← custom operators (raro neste projeto)
├── airflow_settings.yaml         ← connections + variables
├── Dockerfile
├── docker-compose.yml
└── requirements.txt
```

---

## DAG Naming

- **Padrão**: `dag_<dominio>_<acao>`
- **Arquivo**: `dag_<dominio>_<acao>.py`
- **`dag_id`** = nome do arquivo sem `.py`

### Exemplos
- `dag_synthetic_source` — gera dados sintéticos
- `dag_dbt_aws_detailed` — dbt completo (silver→gold→platinum)
- `dag_dbt_aws_silver_only` — apenas silver (futuro)
- `dag_iceberg_optimize` — manutenção mensal Iceberg

---

## Task Naming

- **Padrão**: `<verb>_<noun>` em snake_case
- **Verbos comuns**: `generate`, `upload`, `register`, `validate`, `build`, `test`, `notify`, `optimize`, `vacuum`

### Exemplos
- `generate_data`
- `upload_to_s3`
- `register_partitions`
- `build_silver_clientes`
- `test_gold_models`
- `notify_slack_success`

---

## DAG Skeleton Padrão

```python
"""
DAG: dag_synthetic_source
Domínio: ingestão sintética
Schedule: @daily (00:30 UTC)
Owner: vhmac
"""

from datetime import datetime, timedelta
from pathlib import Path

from airflow import DAG
from airflow.decorators import task, task_group
from airflow.providers.amazon.aws.operators.s3 import S3CreateObjectOperator

from utils.callbacks import slack_failure_callback

DEFAULT_ARGS = {
    "owner": "vhmac",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=10),
    "execution_timeout": timedelta(minutes=20),
    "on_failure_callback": slack_failure_callback,
    "depends_on_past": False,
}

with DAG(
    dag_id="dag_synthetic_source",
    description="Gera dados sintéticos diários para 8 datamarts × 5 tenants",
    schedule="30 0 * * *",  # 00:30 UTC daily
    start_date=datetime(2025, 5, 1),
    catchup=False,
    max_active_runs=1,
    tags=["ingestao", "bronze", "synthetic"],
    default_args=DEFAULT_ARGS,
) as dag:

    @task
    def generate_data(execution_date: str) -> dict:
        """Gera Parquet para todos tenants/datamarts."""
        ...

    @task
    def upload_to_s3(generated: dict) -> list[str]:
        """Upload Parquet para Bronze S3."""
        ...

    @task
    def register_partitions(uris: list[str]) -> None:
        """Registra novas partições no Glue."""
        ...

    register_partitions(upload_to_s3(generate_data("{{ ds }}")))
```

---

## Default Args — Padrão

**Todo DAG inclui**:

```python
DEFAULT_ARGS = {
    "owner": "vhmac",
    "retries": 2,
    "retry_delay": timedelta(minutes=2),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=10),
    "execution_timeout": timedelta(minutes=20),
    "on_failure_callback": slack_failure_callback,    # OBRIGATÓRIO
    "depends_on_past": False,
}
```

### Por quê?
- **`retries=2` + exponential backoff**: tolera falhas transitórias (Athena, S3 throttling)
- **`execution_timeout=20min`**: evita tasks travadas consumindo slot
- **`on_failure_callback` obrigatório**: alerta SNS/Slack
- **`depends_on_past=False`**: backfills paralelos quando seguro

---

## TaskGroups — Por Camada

```python
from airflow.decorators import task_group

with DAG(...) as dag:

    @task_group(group_id="silver_layer")
    def silver_layer():
        build_silver_clientes()
        build_silver_vendas()
        build_silver_titulos()

    @task_group(group_id="gold_layer")
    def gold_layer():
        build_gold_dims()
        build_gold_facts()

    @task_group(group_id="platinum_layer")
    def platinum_layer():
        build_platinum_unit_01()
        build_platinum_unit_02()
        ...

    silver_layer() >> gold_layer() >> platinum_layer()
```

---

## Datasets — Event-Driven

Usar `Dataset` (Airflow 2.4+) para acoplamento entre DAGs sem `ExternalTaskSensor`:

```python
from airflow import Dataset

bronze_vendas = Dataset("s3://elt-pipeline-bronze-dev/comercial/vendas/")

# Producer DAG
with DAG("dag_synthetic_source", ...):
    @task(outlets=[bronze_vendas])
    def write_vendas():
        ...

# Consumer DAG
with DAG(
    "dag_dbt_silver_vendas",
    schedule=[bronze_vendas],  # trigger by Dataset
    ...
):
    ...
```

---

## XCom — Limites

- **NUNCA passar > 1MB** via XCom (PostgreSQL limit)
- Para payloads grandes: salvar em S3, passar URI via XCom

```python
# ❌ Errado
@task
def gerar() -> list[dict]:
    return [{"id": i, ...} for i in range(1_000_000)]  # MB+ via XCom

# ✅ Correto
@task
def gerar() -> str:
    s3_uri = "s3://staging/output.parquet"
    df.to_parquet(s3_uri)
    return s3_uri
```

---

## Pools — Concorrência Athena

Athena tem **limite de queries concorrentes** (default 25 por workgroup, mas custo escala).

Configurar pool dedicado:

```yaml
# airflow_settings.yaml
pools:
  - pool_name: athena_concurrent
    pool_slot: 8
    pool_description: "Limite de queries Athena concorrentes"
```

Tasks Athena usam o pool:

```python
@task(pool="athena_concurrent", pool_slots=1)
def build_gold_fct_vendas():
    ...
```

---

## Callbacks — Padrão Slack

```python
# utils/callbacks.py
import json
import logging
from typing import Any

import boto3

logger = logging.getLogger(__name__)
sns = boto3.client("sns")
SNS_TOPIC_ARN = "arn:aws:sns:us-east-1:..."  # via env var na prática


def slack_failure_callback(context: dict[str, Any]) -> None:
    """Publica falha no SNS → Lambda → Slack."""
    task_instance = context["task_instance"]
    payload = {
        "dag_id": task_instance.dag_id,
        "task_id": task_instance.task_id,
        "execution_date": str(context["execution_date"]),
        "log_url": task_instance.log_url,
        "exception": str(context.get("exception", "unknown")),
        "tenant_id": context.get("params", {}).get("tenant_id", "all"),
    }
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"❌ Airflow Failure: {task_instance.dag_id}",
        Message=json.dumps(payload),
    )
    logger.error("airflow_task_failed", extra=payload)
```

---

## Connections & Variables

### Em código (lookup, não hardcode)

```python
from airflow.hooks.base import BaseHook
from airflow.models import Variable

# Connection
aws_conn = BaseHook.get_connection("aws_default")

# Variable
slack_webhook = Variable.get("slack_webhook_url")
```

### Definidos em `airflow_settings.yaml`

```yaml
connections:
  - conn_id: aws_default
    conn_type: aws
    extra: |
      {
        "region_name": "us-east-1",
        "role_arn": "arn:aws:iam::ACCOUNT:role/elt-pipeline-airflow-role-dev"
      }

variables:
  - variable_name: dbt_target
    variable_value: dev
  - variable_name: slack_webhook_url
    variable_value: "{{ env.SLACK_WEBHOOK_URL }}"
```

**NUNCA commitar secrets** — usar env vars no docker-compose.

---

## Anti-Patterns Airflow

- ❌ Lógica de negócio dentro do DAG file (extrair para `utils/` ou módulo)
- ❌ DAG sem `on_failure_callback`
- ❌ DAG sem `tags`
- ❌ Imports pesados em top-level (lentidão no scheduler)
- ❌ DAG dinâmico sem `globals()[dag_id] = dag` correto
- ❌ XCom com payload > 1MB
- ❌ `BashOperator` quando existe Provider (preferir `S3CreateObjectOperator`, etc.)
- ❌ `schedule_interval` (deprecated → usar `schedule`)
- ❌ `start_date` no passado distante sem `catchup=False`
- ❌ Hardcoded ARNs/connection strings
- ❌ DAG sem `description`
- ❌ Tasks sem `task_id` explícito (TaskFlow gera, mas tornar legível)

---

## Top-Level Code Restriction

Airflow scheduler **parseia DAGs frequentemente**. Top-level deve ser leve.

```python
# ❌ Errado: query a cada parse
from airflow.hooks.postgres_hook import PostgresHook
hook = PostgresHook("postgres")
ROWS = hook.get_records("SELECT ...")  # ❌ executa toda parse

with DAG(...) as dag:
    @task
    def use_rows():
        ...
```

```python
# ✅ Correto: lógica dentro de task
with DAG(...) as dag:
    @task
    def fetch_and_use():
        hook = PostgresHook("postgres")
        rows = hook.get_records("SELECT ...")
        ...
```

---

## Testing DAGs

```python
# tests/dags/test_dag_synthetic_source.py
import pytest
from airflow.models import DagBag

@pytest.fixture
def dagbag():
    return DagBag(dag_folder="airflow/dags", include_examples=False)

def test_dag_loads_without_errors(dagbag):
    assert dagbag.import_errors == {}

def test_synthetic_source_dag(dagbag):
    dag = dagbag.get_dag("dag_synthetic_source")
    assert dag is not None
    assert len(dag.tasks) >= 3
    assert "ingestao" in dag.tags

def test_default_args_have_callback(dagbag):
    dag = dagbag.get_dag("dag_synthetic_source")
    assert dag.default_args.get("on_failure_callback") is not None
```

---

## Referências
- [Airflow Best Practices](https://airflow.apache.org/docs/apache-airflow/stable/best-practices.html)
- [TaskFlow API](https://airflow.apache.org/docs/apache-airflow/stable/tutorial/taskflow.html)
- [python](python.instructions.md) — padrões Python gerais
- [observability](observability.instructions.md) — logging/alerts
- [security](security.instructions.md) — secrets em Airflow
