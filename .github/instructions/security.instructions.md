---
applyTo: '**'
---

# Security

> Padrões de segurança aplicáveis a todo o repositório. Cross-cutting.

---

## Princípios

1. **Zero Trust** — nenhum componente confia em outro por default
2. **Least Privilege** — permissões mínimas necessárias
3. **Defense in Depth** — múltiplas camadas de proteção
4. **Secrets Management** — nunca hardcoded, sempre Secrets Manager / env vars
5. **Audit Trail** — toda ação relevante logada e rastreável

---

## Secrets — Regras Inegociáveis

### NUNCA commitar
- API keys, tokens, webhooks
- Credenciais AWS (access key, secret key)
- ARNs com sufixos sensíveis (account IDs em alguns contextos)
- Connection strings com password
- Certificados privados (.pem, .key)
- Conteúdo de `.env` (apenas `.env.example`)

### `.gitignore` obrigatório

```gitignore
# Secrets
.env
.env.local
.env.*.local
*.pem
*.key
*.p12
*.pfx
secrets/
credentials/

# Terraform
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
.terraform/
.terraform.lock.hcl  # opcional commitar

# AWS
.aws/
```

### Onde armazenar secrets

| Contexto | Onde |
|---|---|
| Local dev | `.env` (gitignored) |
| Airflow runtime | env vars no `docker-compose.yml` referenciando `${VAR}` host |
| Lambda runtime | AWS Secrets Manager via `boto3` |
| GitHub Actions | GitHub Secrets (Settings → Secrets) |
| Slack webhook | AWS Secrets Manager: `elt-pipeline/slack-webhook` |
| dbt profiles | env vars (`{{ env_var('DBT_AWS_ACCESS_KEY_ID') }}`) |

### Pattern: dbt profile

```yaml
# ~/.dbt/profiles.yml ou dbt/profiles.yml (gitignored)
elt_pipeline:
  outputs:
    dev:
      type: athena
      aws_access_key_id: "{{ env_var('AWS_ACCESS_KEY_ID') }}"
      aws_secret_access_key: "{{ env_var('AWS_SECRET_ACCESS_KEY') }}"
      region_name: us-east-1
      s3_staging_dir: s3://elt-pipeline-athena-results-dev/
      database: awsdatacatalog
      schema: gold
      work_group: elt-pipeline-dev
      threads: 4
  target: dev
```

---

## gitleaks — Pre-commit + CI

### Pre-commit hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.2
    hooks:
      - id: gitleaks
```

### CI workflow

```yaml
# .github/workflows/secrets-scan.yml
- uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Quando detectar secret leaked

1. **Imediatamente** rotacionar a credencial
2. **Reescrever histórico** com `git filter-repo` ou BFG
3. **Force push** para apagar do remote (se já pushed)
4. **Notificar** owner do recurso (AWS, Slack admin, etc.)

⚠️ Histórico Git é irreversível em fork público — assumir credencial comprometida.

---

## IAM — Least Privilege

### ❌ NUNCA

```hcl
{
  Effect   = "Allow"
  Action   = "*"             # ❌
  Resource = "*"             # ❌
}
```

```hcl
{
  Effect = "Allow"
  Action = [
    "s3:*"                   # ❌ wildcard de service
  ]
  Resource = "arn:aws:s3:::*"  # ❌ wildcard de resource
}
```

### ✅ Específico

```hcl
{
  Effect = "Allow"
  Action = [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject"
  ]
  Resource = [
    "${aws_s3_bucket.bronze.arn}/*"
  ]
}
```

### Conditions quando aplicável

```hcl
{
  Effect = "Allow"
  Action = "kms:Decrypt"
  Resource = aws_kms_key.platinum.arn
  Condition = {
    StringEquals = {
      "kms:ViaService" = "s3.us-east-1.amazonaws.com"
    }
  }
}
```

### Roles separadas por componente

- `elt-pipeline-airflow-role-<env>` — DAG execution
- `elt-pipeline-dbt-athena-role-<env>` — dbt profile
- `elt-pipeline-lambda-slack-role-<env>` — notification Lambda
- `elt-pipeline-glue-crawler-role-<env>` — Glue crawler (futuro)

---

## S3 — Defaults Obrigatórios

```hcl
# Block public access — TODOS os buckets
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encryption mínima SSE-S3
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning em Bronze (raw recovery)
resource "aws_s3_bucket_versioning" "bronze" {
  bucket = aws_s3_bucket.bronze.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

### KMS para Platinum (SSE-KMS)

Camada Platinum contém dados financeiros consolidados → **SSE-KMS** com chave própria:

```hcl
resource "aws_kms_key" "platinum" {
  description             = "KMS key for platinum layer"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
```

---

## Athena — Workgroup Hardening

```hcl
resource "aws_athena_workgroup" "main" {
  name = var.workgroup_name

  configuration {
    enforce_workgroup_configuration    = true   # ✅ usuários não podem override
    publish_cloudwatch_metrics_enabled = true

    bytes_scanned_cutoff_per_query = 10 * 1024 * 1024 * 1024  # 10 GB

    result_configuration {
      output_location = "s3://${var.results_bucket}/output/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  state = "ENABLED"
}
```

---

## Glue Catalog — Cross-Account Restriction

Por default, Glue catalog é acessível por toda conta. Em ambientes multi-conta:

```hcl
# Glue resource policy explícita
resource "aws_glue_resource_policy" "main" {
  policy = data.aws_iam_policy_document.glue_resource.json
}
```

---

## Secrets Manager — Rotação

Secrets críticos (DB passwords, API keys) devem ter rotação automática:

```hcl
resource "aws_secretsmanager_secret_rotation" "db" {
  secret_id           = aws_secretsmanager_secret.db.id
  rotation_lambda_arn = aws_lambda_function.rotator.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

Slack webhook: rotação manual quando comprometido.

---

## Container Security

### Dockerfile

```dockerfile
# ✅ Pinned versions
FROM python:3.11.6-slim-bookworm

# ✅ Non-root user
RUN useradd --create-home --shell /bin/bash airflow
USER airflow

# ✅ Multi-stage para reduzir surface
FROM python:3.11.6-slim-bookworm AS builder
RUN pip install --no-cache-dir poetry
COPY pyproject.toml poetry.lock ./
RUN poetry export -f requirements.txt > requirements.txt

FROM python:3.11.6-slim-bookworm AS runtime
COPY --from=builder requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
```

### Anti-patterns
- ❌ `FROM python:latest` (não-determinístico)
- ❌ `USER root` no runtime
- ❌ Cache de package manager mantido (aumenta tamanho + leak)
- ❌ Secrets em `ENV` ou `ARG` build-time persistentes

---

## Code Security Scanning

### Python

```bash
# bandit — security linter Python
bandit -r src/ -ll  # apenas medium+ severity
```

### Terraform

```bash
# tfsec — Terraform security scanner
tfsec infra/

# checkov — multi-IaC policy
checkov -d infra/
```

### Dependencies

```bash
# pip-audit — CVE check em deps Python
pip-audit

# dependabot — GitHub managed (configurado em .github/dependabot.yml)
```

---

## Dependency Pinning

```toml
# pyproject.toml
[tool.poetry.dependencies]
python = "^3.11"
dbt-core = "1.7.10"          # ✅ exact pin
dbt-athena-community = "~1.7.0"  # ✅ minor pin
boto3 = "^1.34.0"             # ⚠️ caret = compatible (ok p/ libs estáveis)
```

```hcl
# Terraform
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.0"  # ✅ minor pin
  }
}
```

---

## Logs — PII Awareness

Logs são gravados em CloudWatch / arquivos. **Nunca logar**:
- CPF, CNPJ, RG (mesmo em dev — habituar boas práticas)
- Senhas, tokens, secrets
- Conteúdo de cartões de crédito
- Dados que classificam como sensíveis (LGPD/GDPR)

```python
# ❌ Errado
logger.info(f"User logged in: {user_email}, password={password}")

# ✅ Correto
logger.info("user_login", extra={"user_id_hash": hash(user_email)})
```

---

## Audit Trail

CloudTrail habilitado em todas contas (custo: ~$2/mês por trail):

```hcl
resource "aws_cloudtrail" "main" {
  name                          = "${var.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.audit.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
}
```

---

## Anti-Patterns Security

- ❌ Secrets hardcoded
- ❌ `.env` commitado
- ❌ IAM `Action: "*"`/`Resource: "*"`
- ❌ S3 sem block public access
- ❌ S3 sem encryption
- ❌ Athena workgroup sem `enforce_workgroup_configuration`
- ❌ `print()` de variáveis sensíveis em logs
- ❌ Container rodando como root
- ❌ Dockerfile sem version pinning
- ❌ Bypass de pre-commit (`--no-verify`)
- ❌ Force push em main (apaga audit trail)
- ❌ Histórico Git com secret leaked não-rotacionado

---

## Checklist Pre-Commit

- [ ] Sem secrets hardcoded (gitleaks passou)
- [ ] `.env` não está no commit
- [ ] IAM policies sem wildcards desnecessários
- [ ] S3 buckets com block public access + encryption
- [ ] Logs não expõem PII / secrets
- [ ] Dependencies sem CVEs conhecidos (`pip-audit`)

---

## Referências
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [AWS Well-Architected — Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [terraform](terraform.instructions.md) — security em IaC
- [observability](observability.instructions.md) — audit logs
