"""DAG: dag_synthetic_source

Pipeline de ingestao Bronze:
  generate_and_upload  ->  validate_athena

Modos:
  - Manual trigger (default): gera 1 dia (data execucao) e sobe para S3 Bronze.
  - Backfill historico: usar params start_date/end_date no trigger manual.

Particoes virtuais via Athena Partition Projection (sem batch_create_partition).
"""

from __future__ import annotations

from datetime import datetime, timedelta

from airflow.datasets import Dataset
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from utils.callbacks import task_failure_alert

from airflow import DAG

# ----------------------------------------------------------------------
# Configuracao (Sprint 3 - hardcoded; mover para Variables/Connections em S5)
# ----------------------------------------------------------------------
BRONZE_BUCKET = "elt-pipeline-bronze-dev"
BRONZE_S3_URI = f"s3://{BRONZE_BUCKET}"
GLUE_DATABASE = "bronze_dev"
ATHENA_WORKGROUP = "elt-pipeline-dev"
ATHENA_OUTPUT = "s3://elt-pipeline-athena-results-dev/"

# Dataset publicado ao concluir o pipeline; consumido por dag_dbt_aws_detailed (Sprint 5)
BRONZE_DATASET = Dataset(f"s3://{BRONZE_BUCKET}/")

DEFAULT_ARGS = {
    "owner": "vhmac",
    "retries": 1,
    "retry_delay": timedelta(minutes=2),
    "execution_timeout": timedelta(minutes=30),
    "on_failure_callback": task_failure_alert,
}


def _validate_athena(**context) -> None:
    """Roda SELECT COUNT(*) em vendas para a particao executada e loga o resultado."""
    import time

    import boto3

    logical_date: datetime = context["logical_date"]
    tenant = "unit_01"
    year = logical_date.year
    month = f"{logical_date.month:02d}"
    day = f"{logical_date.day:02d}"

    query = (
        f"SELECT COUNT(*) AS n FROM {GLUE_DATABASE}.vendas "
        f"WHERE tenant_id = '{tenant}' "
        f"AND year = {year} AND month = {int(month)} AND day = {int(day)}"
    )

    client = boto3.client("athena")
    resp = client.start_query_execution(
        QueryString=query,
        WorkGroup=ATHENA_WORKGROUP,
        ResultConfiguration={"OutputLocation": ATHENA_OUTPUT},
    )
    qid = resp["QueryExecutionId"]

    # Poll ate completar (timeout local)
    for _ in range(60):
        status = client.get_query_execution(QueryExecutionId=qid)
        state = status["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(2)

    if state != "SUCCEEDED":
        reason = status["QueryExecution"]["Status"].get("StateChangeReason", "")
        raise RuntimeError(f"Athena query falhou ({state}): {reason}")

    results = client.get_query_results(QueryExecutionId=qid)
    rows = results["ResultSet"]["Rows"]
    # Linha 0 = header, linha 1 = primeiro dado
    count = int(rows[1]["Data"][0]["VarCharValue"]) if len(rows) > 1 else 0
    print(f"validate_athena: vendas {tenant} {year}-{month}-{day} -> {count} linhas")
    if count == 0:
        raise ValueError(f"Particao vazia: {tenant} {year}-{month}-{day}")


with DAG(
    dag_id="dag_synthetic_source",
    description="Bronze ingest: gera dados sinteticos -> S3 -> Athena (Sprint 3)",
    start_date=datetime(2025, 1, 1),
    schedule=None,  # trigger manual; em prod usar @daily
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["bronze", "ingest", "synthetic"],
    params={
        "tenants": "all",
        "datamarts": "all",
        "volume_multiplier": 1.0,
    },
) as dag:

    generate_and_upload = BashOperator(
        task_id="generate_and_upload",
        bash_command=(
            "cd /opt/airflow/data-generator && "
            "PYTHONPATH=src python -m data_generator generate "
            "--tenants {{ params.tenants }} "
            "--datamarts {{ params.datamarts }} "
            "--date {{ ds }} "
            "--output " + BRONZE_S3_URI + " "
            "--volume-multiplier {{ params.volume_multiplier }}"
        ),
    )

    validate_athena = PythonOperator(
        task_id="validate_athena",
        python_callable=_validate_athena,
        outlets=[BRONZE_DATASET],
    )

    generate_and_upload >> validate_athena
