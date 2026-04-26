# ============================================================
# Modulo: secrets-manager
# Cria placeholders para secrets que serao usados em Sprints futuras:
#   - slack-webhook-url       (Sprint 6 - Lambda notifier)
#   - dbt-athena-credentials  (alternativa a profile YAML local)
#
# Os values sao placeholders ("CHANGE_ME"); substituir via Console
# ou `aws secretsmanager put-secret-value` antes de uso real.
#
# Custo: $0.40/mes por secret (independente de versoes).
# ============================================================

resource "aws_secretsmanager_secret" "slack_webhook" {
  name        = "${var.name_prefix}/${var.env}/slack-webhook-url"
  description = "Slack incoming webhook URL para notificacoes de pipeline"
  tags        = merge(var.tags, { Component = "secret-slack" })

  recovery_window_in_days = 0 # delete imediato em destroy (dev only)
}

resource "aws_secretsmanager_secret_version" "slack_webhook_placeholder" {
  secret_id     = aws_secretsmanager_secret.slack_webhook.id
  secret_string = jsonencode({ webhook_url = "CHANGE_ME" })

  lifecycle {
    ignore_changes = [secret_string] # nao sobrescrever valor real depois
  }
}
