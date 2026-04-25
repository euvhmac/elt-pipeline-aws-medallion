---
applyTo: '**'
---

# Observability

> Padrões de logging estruturado, métricas, alerting e tracing. Cross-cutting.

---

## Os 3 Pilares

```
┌─────────────────────────────────────────────────┐
│  Logs       │  Metrics      │  Traces           │
│  (eventos)  │  (números)    │  (rastros e2e)    │
├─────────────┼───────────────┼───────────────────┤
│  CloudWatch │  CloudWatch   │  dag_run_id       │
│  Logs       │  Metrics      │  como trace ID    │
│             │               │  (Phase 2:        │
│             │               │  OpenTelemetry)   │
└─────────────┴───────────────┴───────────────────┘
```

---

## Logging — Estruturado JSON

### Formato padrão

```json
{
  "timestamp": "2025-04-25T14:32:01.123Z",
  "level": "INFO",
  "service": "data-generator",
  "message": "venda_gerada",
  "tenant_id": "unit_01",
  "dag_id": "dag_synthetic_source",
  "task_id": "generate_data",
  "request_id": "manual__2025-04-25T14:00:00",
  "context": {
    "venda_id": "v-12345",
    "vlr_total": "1500.00"
  }
}
```

### Campos obrigatórios

| Campo | Tipo | Origem |
|---|---|---|
| `timestamp` | ISO 8601 UTC | Auto via formatter |
| `level` | DEBUG/INFO/WARNING/ERROR/CRITICAL | logger |
| `service` | string | nome do componente |
| `message` | string snake_case | event name |

### Campos contextuais (quando aplicável)

| Campo | Quando incluir |
|---|---|
| `tenant_id` | Operação por tenant |
| `dag_id` | Em código Airflow |
| `task_id` | Em tasks Airflow |
| `request_id` / `trace_id` | Em Lambdas, requests |
| `model_name` | Em logs dbt |
| `error` / `exception` | Em ERRORs |

### Implementação Python

```python
# utils/logging.py
import logging
import json
from datetime import datetime
from typing import Any


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.utcfromtimestamp(record.created).isoformat() + "Z",
            "level": record.levelname,
            "service": getattr(record, "service", record.name),
            "message": record.getMessage(),
        }
        # Inclui campos extras passados via `extra={}`
        for key, value in record.__dict__.items():
            if key not in (
                "name", "msg", "args", "levelname", "levelno", "pathname",
                "filename", "module", "exc_info", "exc_text", "stack_info",
                "lineno", "funcName", "created", "msecs", "relativeCreated",
                "thread", "threadName", "processName", "process", "service",
                "message",
            ):
                payload[key] = value

        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        return json.dumps(payload, default=str)


def get_logger(service: str) -> logging.Logger:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    logger = logging.getLogger(service)
    logger.handlers = [handler]
    logger.setLevel(logging.INFO)
    logger.propagate = False
    return logger
```

### Uso

```python
from utils.logging import get_logger

logger = get_logger("data-generator")

logger.info(
    "venda_gerada",
    extra={
        "tenant_id": "unit_01",
        "venda_id": "v-12345",
        "vlr_total": "1500.00",
    },
)
```

---

## Log Levels — Quando Usar

| Level | Quando |
|---|---|
| `DEBUG` | Detalhes de troubleshooting (off em produção) |
| `INFO` | Eventos normais (start, success, item processado) |
| `WARNING` | Anomalias recuperáveis (retry, fallback) |
| `ERROR` | Falhas que afetam operação (mas processo continua) |
| `CRITICAL` | Falhas que requerem intervenção humana |

---

## Métricas — CloudWatch

### Namespace padrão

```
elt-pipeline/<component>/<metric_name>
```

Exemplos:
- `elt-pipeline/airflow/dag_runs_total`
- `elt-pipeline/dbt/tests_failed`
- `elt-pipeline/lambda/slack_notify_duration`
- `elt-pipeline/synthetic/records_generated`

### Pattern Lambda → CloudWatch

```python
import boto3
from datetime import datetime

cloudwatch = boto3.client("cloudwatch")

def emit_metric(
    namespace: str,
    metric_name: str,
    value: float,
    unit: str = "Count",
    dimensions: list[dict[str, str]] | None = None,
) -> None:
    cloudwatch.put_metric_data(
        Namespace=namespace,
        MetricData=[{
            "MetricName": metric_name,
            "Value": value,
            "Unit": unit,
            "Timestamp": datetime.utcnow(),
            "Dimensions": dimensions or [],
        }],
    )

# Uso
emit_metric(
    namespace="elt-pipeline/synthetic",
    metric_name="records_generated",
    value=1500,
    unit="Count",
    dimensions=[
        {"Name": "tenant_id", "Value": "unit_01"},
        {"Name": "datamart", "Value": "comercial"},
    ],
)
```

### Métricas-chave a coletar

| Componente | Métrica | Unit |
|---|---|---|
| Airflow | `dag_run_duration_seconds` | Seconds |
| Airflow | `task_failures_total` | Count |
| dbt | `models_built_total` | Count |
| dbt | `tests_failed_total` | Count |
| dbt | `model_duration_seconds` | Seconds |
| Athena | `bytes_scanned_total` (via workgroup metrics) | Bytes |
| Synthetic | `records_generated_total` | Count |
| Lambda | `invocations` (auto) + custom | Count |

---

## Alerting — SNS → Lambda → Slack

### Critério para alerta

Alertas enviados quando:
- DAG falha (após retries esgotados)
- dbt test severity=error falha
- Source freshness > error_after threshold
- Athena query exceeds bytes_scanned_cutoff
- Budget AWS > 80% do limite
- Lambda function error rate > 5%

### Latency target

**< 60s** entre evento e mensagem no Slack.

### Mensagem padrão Slack

```json
{
  "username": "ELT Pipeline Alerts",
  "icon_emoji": ":warning:",
  "attachments": [{
    "color": "danger",
    "title": "❌ Airflow DAG Failed: dag_synthetic_source",
    "title_link": "https://airflow.../dags/dag_synthetic_source/grid",
    "fields": [
      {"title": "Task", "value": "generate_data", "short": true},
      {"title": "Tenant", "value": "unit_01", "short": true},
      {"title": "Time", "value": "2025-04-25 14:32 UTC", "short": true},
      {"title": "Logs", "value": "<URL>", "short": false}
    ],
    "footer": "elt-pipeline-aws-medallion",
    "ts": 1714056721
  }]
}
```

### Lambda notifier

```python
# lambda/slack_notifier/handler.py
import json
import os
import urllib.request

SLACK_WEBHOOK_URL = os.environ["SLACK_WEBHOOK_URL"]  # via Secrets Manager


def lambda_handler(event: dict, context) -> dict:
    """Recebe SNS message, formata e envia para Slack."""
    for record in event["Records"]:
        sns_message = json.loads(record["Sns"]["Message"])
        slack_payload = format_slack(sns_message)

        req = urllib.request.Request(
            SLACK_WEBHOOK_URL,
            data=json.dumps(slack_payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        urllib.request.urlopen(req, timeout=5)

    return {"statusCode": 200}


def format_slack(message: dict) -> dict:
    ...  # build attachment
```

---

## dbt Artifacts — S3 Upload

Toda execução dbt deve fazer upload de artifacts para análise posterior:

```bash
# Após dbt build
aws s3 cp target/manifest.json \
  s3://elt-pipeline-dbt-artifacts-prd/${RUN_ID}/manifest.json

aws s3 cp target/run_results.json \
  s3://elt-pipeline-dbt-artifacts-prd/${RUN_ID}/run_results.json

aws s3 cp target/sources.json \
  s3://elt-pipeline-dbt-artifacts-prd/${RUN_ID}/sources.json
```

### Uso futuro
- **dbt-artifacts package**: ingere artifacts em modelos para metadata analysis
- **Elementary**: alertas de qualidade baseados em artifacts
- **Lineage**: extração via `manifest.json`

---

## CloudWatch Retention

```hcl
resource "aws_cloudwatch_log_group" "airflow" {
  name              = "/elt-pipeline/airflow/${var.env}"
  retention_in_days = 30  # 30 dias default
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.lambda_name}"
  retention_in_days = 30
}
```

### Custo
- 30 dias retention = ~$0.50/GB armazenado (após primeira semana free)
- Logs verbosos: cuidado com volume

---

## Trace ID

**Sem OpenTelemetry inicial** (Phase 2). Por enquanto:

- **Airflow**: usar `dag_run_id` ou `run_id` como trace ID
- **Lambda**: usar request ID do CloudWatch (`context.aws_request_id`)
- **dbt**: gerar UUID ao iniciar e propagar via env var

```python
# Em DAG
@task
def my_task(**context):
    trace_id = context["dag_run"].run_id
    logger.info("task_started", extra={"trace_id": trace_id})
```

---

## Dashboards CloudWatch

Dashboards-chave a criar (Sprint 5):

1. **`elt-pipeline-overview`**
   - DAG runs success rate (24h)
   - Airflow task failures (24h)
   - dbt models built / failed
   - Athena bytes scanned (custo proxy)

2. **`elt-pipeline-quality`**
   - dbt tests passed/failed
   - Source freshness violations
   - Singular tests fired

3. **`elt-pipeline-cost`**
   - Athena bytes scanned por workgroup
   - S3 storage por bucket
   - Lambda invocations + duration

---

## Anti-Patterns Observability

- ❌ `print()` em produção
- ❌ Logs não-estruturados (`f"User {x} did {y}"` sem JSON)
- ❌ Logar PII / secrets
- ❌ Sem `tenant_id` em logs multi-tenant
- ❌ Failures sem alerta
- ❌ Alertas sem ação clara (alert fatigue)
- ❌ Logs sem retention policy (custo infinito)
- ❌ DAGs sem `on_failure_callback`
- ❌ Métricas sem dimensions (não dá para drill-down)
- ❌ Dashboards manuais (preferir Terraform)

---

## Checklist Observability

Para todo componente novo:
- [ ] Logging estruturado JSON configurado
- [ ] Logger com campos obrigatórios (`timestamp`, `level`, `service`)
- [ ] Métricas críticas emitidas para CloudWatch
- [ ] Falhas críticas disparam SNS → Slack
- [ ] Logs com retention < 30 dias (default)
- [ ] PII / secrets removidos de logs
- [ ] Dashboard incluído no `elt-pipeline-overview`

---

## Referências
- [Twelve-Factor App — Logs](https://12factor.net/logs)
- [structlog](https://www.structlog.org/)
- [CloudWatch Embedded Metric Format](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format.html)
- [airflow](airflow.instructions.md) — callbacks
- [security](security.instructions.md) — não logar PII
