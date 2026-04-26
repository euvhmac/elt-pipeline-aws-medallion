"""Callbacks compartilhados entre DAGs.

Sprint 5: logging estruturado JSON.
Sprint 6: publica em SNS topic quando PIPELINE_ALERTS_TOPIC_ARN esta setado;
          Lambda slack-notifier consome e posta no Slack.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any

logger = logging.getLogger("airflow.callbacks")

_TOPIC_ARN_ENV = "PIPELINE_ALERTS_TOPIC_ARN"


def _publish_sns(payload: dict[str, Any]) -> None:
    """Publica payload no SNS quando ARN configurado; falha silenciosamente."""
    topic_arn = os.environ.get(_TOPIC_ARN_ENV)
    if not topic_arn:
        return
    try:
        import boto3

        boto3.client("sns").publish(
            TopicArn=topic_arn,
            Subject=f"[Airflow] {payload.get('event')} - {payload.get('dag_id')}",
            Message=json.dumps(payload, default=str),
        )
    except Exception as exc:
        # Nao deixar callback derrubar a task original; so logar
        logger.warning(json.dumps({"event": "sns_publish_failed", "error": repr(exc)}))


def _emit(level: int, event: str, context: dict[str, Any]) -> None:
    task_instance = context.get("task_instance")
    dag_run = context.get("dag_run")
    payload = {
        "event": event,
        "dag_id": context.get("dag").dag_id if context.get("dag") else None,
        "task_id": task_instance.task_id if task_instance else None,
        "run_id": dag_run.run_id if dag_run else None,
        "try_number": task_instance.try_number if task_instance else None,
        "log_url": task_instance.log_url if task_instance else None,
    }
    exception = context.get("exception")
    if exception is not None:
        payload["exception"] = repr(exception)
    logger.log(level, json.dumps(payload, default=str))
    if level >= logging.ERROR:
        _publish_sns(payload)


def task_failure_alert(context: dict[str, Any]) -> None:
    """on_failure_callback: log estruturado + SNS publish (Sprint 6)."""
    _emit(logging.ERROR, "task_failed", context)


def task_success_alert(context: dict[str, Any]) -> None:
    """on_success_callback opcional: apenas log (sem SNS)."""
    _emit(logging.INFO, "task_succeeded", context)
