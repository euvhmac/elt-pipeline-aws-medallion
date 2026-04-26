"""Lambda slack-notifier.

Trigger: SNS topic `pipeline-alerts`.
Acao: le webhook URL do Secrets Manager, formata Slack Block Kit, POST.

Sem dependencias externas (urllib + boto3 ja vem na runtime python3.11).
"""

from __future__ import annotations

import json
import logging
import os
import urllib.request
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRET_ARN = os.environ["SLACK_SECRET_ARN"]
_secrets_client = boto3.client("secretsmanager")
_webhook_cache: dict[str, str] = {}


def _get_webhook() -> str:
    if "url" not in _webhook_cache:
        resp = _secrets_client.get_secret_value(SecretId=SECRET_ARN)
        payload = json.loads(resp["SecretString"])
        _webhook_cache["url"] = payload["webhook_url"]
    return _webhook_cache["url"]


def _format_blocks(message: dict[str, Any]) -> dict[str, Any]:
    event = message.get("event", "task_failed")
    color = "#dc3545" if event == "task_failed" else "#28a745"
    fields = []
    for key in ("dag_id", "task_id", "run_id", "try_number"):
        value = message.get(key)
        if value is not None:
            fields.append({"title": key, "value": str(value), "short": True})

    attachment: dict[str, Any] = {
        "color": color,
        "title": f"Airflow: {event}",
        "fields": fields,
        "footer": "elt-pipeline-aws-medallion",
    }
    if message.get("log_url"):
        attachment["title_link"] = message["log_url"]
    if message.get("exception"):
        attachment["text"] = f"```{message['exception'][:1500]}```"

    return {"username": "ELT Pipeline Alerts", "attachments": [attachment]}


def lambda_handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    webhook = _get_webhook()
    sent = 0

    for record in event.get("Records", []):
        sns_message = record["Sns"]["Message"]
        try:
            parsed = json.loads(sns_message)
        except json.JSONDecodeError:
            parsed = {"event": "raw_message", "exception": sns_message}

        body = _format_blocks(parsed)
        req = urllib.request.Request(
            webhook,
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            status = resp.status
            logger.info(json.dumps({"event": "slack_post", "status": status, "dag_id": parsed.get("dag_id")}))
        sent += 1

    return {"statusCode": 200, "sent": sent}
