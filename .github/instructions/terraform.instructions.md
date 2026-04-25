---
applyTo: 'infra/**/*.tf'
---

# Terraform — Infrastructure as Code

> Padrões para Terraform 1.7+ provisionando AWS (S3, Glue, Athena, Lambda, SNS, IAM, Secrets Manager, DynamoDB).

---

## Versão & Provider

```hcl
# infra/envs/dev/versions.tf
terraform {
  required_version = "~> 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "elt-pipeline-tfstate"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "elt-pipeline-tfstate-lock"
  }
}
```

### Regras
- **Provider pinning** sempre com `~>` (lock minor)
- **Backend remoto S3 + DynamoDB lock** obrigatório (nunca local em prd)
- **Encrypt = true** no state

---

## Estrutura de Pastas

```
infra/
├── envs/
│   ├── dev/
│   │   ├── main.tf            ← composition (chama modules)
│   │   ├── variables.tf       ← env-specific inputs
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── terraform.tfvars   ← gitignored se contiver secrets
│   └── prd/
│       └── ...
├── modules/
│   ├── s3-medallion/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── README.md          ← uso, inputs, outputs, exemplos
│   ├── glue-catalog/
│   ├── iam-roles/
│   ├── secrets-manager/
│   ├── athena-workgroup/
│   └── sns-lambda-slack/
└── README.md
```

---

## Module Structure — Obrigatório

Cada module tem **exatamente** esses arquivos:

| Arquivo | Conteúdo |
|---|---|
| `main.tf` | Recursos principais |
| `variables.tf` | Inputs com `description` e `validation` |
| `outputs.tf` | Outputs com `description` |
| `versions.tf` | `terraform {}` block |
| `README.md` | Propósito, inputs/outputs, exemplo de uso |

---

## Naming AWS — Padrão

```
<project>-<component>-<env>
```

- **kebab-case** lowercase
- **Sem underscores** (compatibilidade DNS S3)
- **Sufixo `<env>`** sempre

### Variável padrão `name_prefix`:

```hcl
# variables.tf do module
variable "name_prefix" {
  type        = string
  description = "Prefixo de nomes (ex: 'elt-pipeline-dev')"
}

# uso
resource "aws_s3_bucket" "bronze" {
  bucket = "${var.name_prefix}-bronze"
}
```

Detalhes em [naming-conventions](naming-conventions.instructions.md).

---

## Tagging — `default_tags`

**Obrigatório** em provider config:

```hcl
# infra/envs/dev/main.tf
provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "elt-pipeline-aws-medallion"
      Environment = var.env
      ManagedBy   = "Terraform"
      Owner       = "vhmac"
      Repository  = "github.com/euvhmac/elt-pipeline-aws-medallion"
    }
  }
}
```

### Tags por recurso (override quando necessário)

```hcl
resource "aws_s3_bucket" "bronze" {
  bucket = "${var.name_prefix}-bronze"

  tags = {
    Component = "storage-bronze"
    Layer     = "bronze"
  }
}
```

---

## Variables — Validation

**Sempre validar inputs críticos**:

```hcl
variable "env" {
  type        = string
  description = "Ambiente de deploy"

  validation {
    condition     = contains(["dev", "prd"], var.env)
    error_message = "env deve ser 'dev' ou 'prd'."
  }
}

variable "tenant_ids" {
  type        = list(string)
  description = "Lista de tenants suportados"
  default     = ["unit_01", "unit_02", "unit_03", "unit_04", "unit_05"]

  validation {
    condition = alltrue([
      for t in var.tenant_ids : can(regex("^unit_0[1-5]$", t))
    ])
    error_message = "Cada tenant deve seguir padrão 'unit_0[1-5]'."
  }
}

variable "athena_bytes_scanned_cutoff_gb" {
  type        = number
  description = "Limite de bytes scanned por query Athena (GB)"
  default     = 10

  validation {
    condition     = var.athena_bytes_scanned_cutoff_gb > 0 && var.athena_bytes_scanned_cutoff_gb <= 100
    error_message = "Cutoff deve estar entre 1 e 100 GB."
  }
}
```

---

## Outputs — Documentados

```hcl
# outputs.tf
output "bronze_bucket_arn" {
  value       = aws_s3_bucket.bronze.arn
  description = "ARN do bucket S3 Bronze (raw data)"
}

output "bronze_bucket_name" {
  value       = aws_s3_bucket.bronze.bucket
  description = "Nome do bucket S3 Bronze"
}

output "athena_workgroup_name" {
  value       = aws_athena_workgroup.main.name
  description = "Nome do Athena Workgroup principal"
}
```

---

## Security Defaults

### S3 buckets

```hcl
resource "aws_s3_bucket" "bronze" {
  bucket = "${var.name_prefix}-bronze"
}

resource "aws_s3_bucket_versioning" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # SSE-S3 mínimo; KMS para Platinum
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365  # delete after 1 year (ajustar)
    }
  }
}
```

### IAM — Least Privilege

```hcl
# ✅ Específico
resource "aws_iam_policy" "dbt_athena" {
  name = "${var.name_prefix}-dbt-athena"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
        ]
        Resource = aws_athena_workgroup.main.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.bronze.arn,
          "${aws_s3_bucket.bronze.arn}/*",
        ]
      },
    ]
  })
}
```

```hcl
# ❌ NUNCA fazer
{
  Effect   = "Allow"
  Action   = "*"          # ❌
  Resource = "*"          # ❌
}
```

### Athena Workgroup

```hcl
resource "aws_athena_workgroup" "main" {
  name = "${var.name_prefix}"

  configuration {
    enforce_workgroup_configuration    = true   # ✅ obrigatório
    publish_cloudwatch_metrics_enabled = true

    bytes_scanned_cutoff_per_query = var.athena_bytes_scanned_cutoff_gb * 1024 * 1024 * 1024

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/output/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
}
```

### Secrets Manager

```hcl
resource "aws_secretsmanager_secret" "slack_webhook" {
  name        = "${var.name_prefix}/slack-webhook"
  description = "Slack webhook URL para notificações"
}

# Valor inicial via CLI ou console (NUNCA hardcoded em .tf)
# aws secretsmanager put-secret-value --secret-id ... --secret-string ...
```

---

## State Management

### Backend obrigatório

```hcl
backend "s3" {
  bucket         = "elt-pipeline-tfstate"
  key            = "envs/dev/terraform.tfstate"
  region         = "us-east-1"
  encrypt        = true
  dynamodb_table = "elt-pipeline-tfstate-lock"
}
```

### Bootstrap

State backend (S3 + DynamoDB) é provisionado **manualmente uma única vez** ou via módulo bootstrap separado (não em `terraform apply` recorrente).

### Workflow

```bash
# Init
terraform -chdir=infra/envs/dev init

# Plan (preview)
terraform -chdir=infra/envs/dev plan -out=tfplan

# Apply (após PR review do plan)
terraform -chdir=infra/envs/dev apply tfplan

# Destroy (cuidado, env-only)
terraform -chdir=infra/envs/dev destroy
```

---

## CI/CD Workflow (Sprint 7)

```yaml
# .github/workflows/terraform-ci.yml
- terraform fmt -check -recursive
- terraform validate
- terraform plan -out=tfplan       # comentado em PR
- tflint --recursive
- tfsec .                           # security scan
- checkov -d infra/                 # policy compliance
```

**Nunca apply automático** — `apply` só após PR merge + manual approval.

---

## Anti-Patterns Terraform

- ❌ State local (`terraform.tfstate` em git)
- ❌ Provider sem version pinning (`version = ">= 5"` muito amplo)
- ❌ Hardcoded ARNs/IDs (usar `data` source)
- ❌ Recursos sem tags
- ❌ IAM `Action: "*"` ou `Resource: "*"`
- ❌ S3 sem block public access
- ❌ S3 sem encryption
- ❌ S3 sem versioning (Bronze pelo menos)
- ❌ Secrets em `.tf` files
- ❌ Variables sem `description`
- ❌ Outputs sem `description`
- ❌ Module sem `README.md`
- ❌ `count` quando `for_each` é melhor (loop sobre map)
- ❌ Misturar lógica de envs no mesmo state
- ❌ `terraform apply` direto em prd sem PR

---

## Formatação

```bash
terraform fmt -recursive
```

Pre-commit hook obrigatório (Sprint 7):

```yaml
- repo: https://github.com/antonbabenko/pre-commit-terraform
  rev: v1.83.5
  hooks:
    - id: terraform_fmt
    - id: terraform_validate
    - id: terraform_tflint
```

---

## Module Example — `s3-medallion`

```hcl
# infra/modules/s3-medallion/main.tf
locals {
  layers = ["bronze", "silver", "gold", "platinum", "athena-results", "dbt-artifacts"]
}

resource "aws_s3_bucket" "this" {
  for_each = toset(local.layers)
  bucket   = "${var.name_prefix}-${each.key}"

  tags = {
    Component = "storage-${each.key}"
    Layer     = each.key
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id

  versioning_configuration {
    status = each.key == "bronze" ? "Enabled" : "Suspended"
  }
}
```

---

## Referências
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [security](security.instructions.md) — IAM e encryption
- [cost-awareness](cost-awareness.instructions.md) — custo dos recursos
- [naming-conventions](naming-conventions.instructions.md)
