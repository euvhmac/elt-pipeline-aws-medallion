"""Callbacks compartilhados entre DAGs.

Sprint 5: apenas logging estruturado JSON.
Sprint 6: integrar SNS -> Lambda -> Slack.
"""

from __future__ import annotations

import json
import logging
from typing import Any

logger = logging.getLogger("airflow.callbacks")


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


def task_failure_alert(context: dict[str, Any]) -> None:
    """on_failure_callback: loga falha estruturada (Sprint 6 publica em SNS)."""
    _emit(logging.ERROR, "task_failed", context)


def task_success_alert(context: dict[str, Any]) -> None:
    """on_success_callback opcional: loga sucesso (uso seletivo)."""
    _emit(logging.INFO, "task_succeeded", context)
