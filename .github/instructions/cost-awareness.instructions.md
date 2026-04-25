---
applyTo: '{infra,dbt}/**'
---

# Cost Awareness — Anti-Burn AWS

> Padrões para manter custo AWS em ~$5-7/mês (vs $800/mês baseline). Aplica a Terraform e dbt.

---

## Budget Target

- **Free tier ($200 créditos)**: deve durar 12+ meses
- **Custo recorrente esperado**: $5-7/mês (S3 + DynamoDB + CloudWatch)
- **Picos aceitáveis**: até $15/mês durante Sprint de carga (geração de dados)
- **Budget alert**: $10/mês warn (80%), $15/mês critical (120%)

---

## Athena — O Maior Risco

### Pricing
- **$5 por TB scanned** (us-east-1)
- 1 query mal escrita = $5+
- 100 queries diárias × 1GB cada = $0.50/dia = $15/mês

### Mitigações OBRIGATÓRIAS

#### 1. Workgroup com cutoff

```hcl
configuration {
  bytes_scanned_cutoff_per_query = 10 * 1024 * 1024 * 1024  # 10 GB
  enforce_workgroup_configuration = true
}
```

Queries acima de 10 GB **falham automaticamente**.

#### 2. Partition pruning obrigatório

Toda query em fato grande tem `WHERE tenant_id = ...` + `WHERE dt_*`:

```sql
-- ✅ Correto
SELECT *
FROM gold.fct_vendas
WHERE tenant_id = 'unit_01'
  AND dt_venda >= DATE '2024-01-01'
  AND dt_venda < DATE '2024-02-01'
```

Detalhes em [sql-athena](sql-athena.instructions.md).

#### 3. EXPLAIN ANALYZE em PRs

Modelos Gold/Platinum complexos: incluir output de `EXPLAIN ANALYZE` no PR description (template já contempla).

#### 4. Compressão obrigatória

```sql
-- dbt config
{{
  config(
    table_type='iceberg',
    format='parquet',
    table_properties={
      'write.parquet.compression-codec': 'zstd',  -- ou 'snappy'
    }
  )
}}
```

---

## S3 — Storage Lifecycle

### Pricing
- **Standard**: $0.023/GB/mês
- **Standard-IA**: $0.0125/GB/mês (50% off)
- **Glacier Instant**: $0.004/GB/mês (83% off)
- **Glacier Deep Archive**: $0.00099/GB/mês (96% off)

### Lifecycle policy padrão

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    id     = "tiered-storage"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365  # delete após 1 ano (ajustar)
    }
  }

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
```

### Anti-patterns S3
- ❌ Bucket sem lifecycle policy (cresce indefinidamente)
- ❌ Versioning em todas camadas (Bronze sim, Silver/Gold não)
- ❌ Multipart uploads abortados não-limpos
- ❌ Logs sem retention

---

## Iceberg — Manutenção Regular

### Por que importa
- Iceberg cria muitos arquivos pequenos em writes incrementais
- Athena cobra por arquivo scanned (overhead)
- Sem manutenção, custo escala

### OPTIMIZE (mensal)

```sql
OPTIMIZE gold.fct_vendas REWRITE DATA USING BIN_PACK;
```

Junta arquivos pequenos em arquivos > 128 MB. Reduz scan time.

### VACUUM (mensal, retention 7d)

```sql
VACUUM gold.fct_vendas;  -- remove snapshots > 7 dias
```

### DAG dedicado

```python
# dag_iceberg_optimize.py — schedule mensal
with DAG("dag_iceberg_optimize", schedule="0 4 1 * *", ...):
    for table in GOLD_TABLES:
        optimize_table(table)
        vacuum_table(table)
```

---

## Lambda — Right-Sizing

### Pricing
- $0.20 per 1M requests
- $0.0000166667 per GB-second

### Defaults baratos

```hcl
resource "aws_lambda_function" "slack_notifier" {
  runtime = "python3.11"
  memory_size = 128             # ✅ mínimo (256MB se precisar de boto3)
  timeout = 10                  # ✅ enxuto (Slack webhook é rápido)
  architectures = ["arm64"]     # ✅ 20% mais barato que x86
}
```

### Anti-patterns Lambda
- ❌ `memory_size = 1024` quando 128MB resolve
- ❌ `timeout = 900` (15 min) quando 30s resolve
- ❌ x86 quando arm64 funciona
- ❌ Cold start ignorado (provisioned concurrency em alto throughput)

---

## CloudWatch — Custo de Logs

### Pricing
- **Ingestion**: $0.50/GB
- **Storage**: $0.03/GB/mês
- **Queries (Insights)**: $0.005/GB scanned

### Retention default

```hcl
resource "aws_cloudwatch_log_group" "this" {
  retention_in_days = 30  # ✅ default deste projeto
}
```

### Volume control
- Logs DEBUG OFF em produção
- Não logar payload completo (apenas IDs + sizes)
- Não logar dentro de loops apertados

---

## Glue Catalog — Free para Maioria

- **Primeiros 1M objects**: free
- **Acima**: $1 / 100K objects / mês
- Praticamente free neste projeto (~50 tabelas)

### Crawlers (futuro)
- $0.44 / DPU-hour
- Rodar **apenas em Bronze** (Silver+ é dbt-managed)
- Schedule semanal, não diário

---

## DynamoDB — Apenas TF Lock

- **Pricing on-demand**: $1.25 / 1M write requests
- TF lock: ~10 writes/dia = $0/mês

```hcl
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "elt-pipeline-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"   # ✅ on-demand
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

---

## Budget Alerts — OBRIGATÓRIO

```hcl
resource "aws_budgets_budget" "monthly" {
  name              = "elt-pipeline-monthly"
  budget_type       = "COST"
  limit_amount      = "10"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["euvhmendes@gmail.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["euvhmendes@gmail.com"]
  }
}
```

---

## Cost Allocation Tags

Tags `Project`, `Environment`, `Component` ativadas em **AWS Cost Explorer** permitem breakdown:

```
Cost by Project = elt-pipeline-aws-medallion
├── bronze (storage)         → $1.20
├── silver (storage)         → $0.80
├── gold (storage)           → $0.40
├── athena (compute)         → $2.50
├── airflow (compute local)  → $0.00
└── lambda (notifications)   → $0.10
                              -------
                              $5.00/mês
```

---

## PR Checklist — Cost Impact

Para PRs que adicionam recursos AWS, incluir no PR description:

```markdown
## 💰 Custo AWS Estimado

| Recurso | Custo/mês |
|---|---|
| S3 Bronze (10 GB) | $0.23 |
| Athena (3 TB scanned) | $15.00 |
| Lambda (10K invocations) | $0.00 |
| **Total adicionado** | **$15.23** |

**Mitigações aplicadas**:
- ✅ Workgroup cutoff 10 GB
- ✅ Lifecycle policy bronze 30d → IA
- ✅ Lambda arm64 + 128MB
```

---

## Calculadora Mental

| Operação | Custo aproximado |
|---|---|
| Scan 1 TB no Athena | $5.00 |
| Storage 100 GB S3 Standard / mês | $2.30 |
| Storage 100 GB S3 IA / mês | $1.25 |
| 1M Lambda invocations (128MB, 1s) | $0.20 + $2.08 = $2.28 |
| 1 GB CloudWatch logs ingested | $0.50 |
| 1M Glue catalog requests | $1.00 |

---

## Anti-Patterns Cost

- ❌ Athena query sem partition predicate
- ❌ S3 bucket sem lifecycle
- ❌ CloudWatch sem retention
- ❌ Iceberg sem OPTIMIZE/VACUUM mensal
- ❌ Lambda over-provisioned (1GB quando 128MB resolve)
- ❌ Lambda x86 (sem motivo) em vez de arm64
- ❌ Glue crawler diário em Silver+ (dbt-managed)
- ❌ Versioning S3 em todas camadas
- ❌ Multipart uploads não-limpos
- ❌ DynamoDB provisioned (deveria ser on-demand)
- ❌ NAT Gateway desnecessário ($30/mês cada!)
- ❌ Snapshots EBS / RDS antigos não-limpos
- ❌ Reservas (RIs/Savings Plans) em workload variável

---

## Otimizações Futuras (Phase 2)

- [ ] Athena Iceberg metadata cache (reduz catalog calls)
- [ ] S3 Intelligent-Tiering em camadas com acesso variável
- [ ] CloudWatch Logs Insights queries específicos vs full scan
- [ ] Lambda SnapStart para Java/Python (cold start)
- [ ] Glue Crawlers serverless apenas em Bronze, schedule semanal

---

## Referências
- [AWS Pricing Calculator](https://calculator.aws/)
- [Athena Cost Optimization](https://aws.amazon.com/athena/pricing/)
- [S3 Pricing](https://aws.amazon.com/s3/pricing/)
- [docs/COST_ESTIMATE.md](../../docs/COST_ESTIMATE.md) — breakdown completo
- [terraform](terraform.instructions.md)
- [sql-athena](sql-athena.instructions.md) — partition pruning
