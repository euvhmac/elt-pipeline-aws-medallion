# Estimativa de Custos AWS

Análise transparente do custo mensal esperado, considerando volume sintético e free tier.

## Resumo Executivo

| Cenário | Custo Mensal Estimado |
|---|---|
| **Free Tier ativo (primeiros 12 meses)** | **$0 - $3** |
| Pós Free Tier (volume baixo) | $5 - $15 |
| Pós Free Tier (volume produção) | $30 - $80 |

> Para portfólio: utilizando free tier + créditos $200, o projeto pode rodar **~12 meses sem custo direto**.

---

## Volume Considerado

| Item | Volume |
|---|---|
| Tenants ativos | 5 (`unit_01` a `unit_05`) |
| Datamarts | 8 |
| Linhas geradas/dia | ~550k |
| Tamanho Parquet/dia | ~150 MB |
| Storage cumulativo (90 dias) | ~25 GB (todas as camadas) |
| Execuções dbt build/dia | 1 (full pipeline) |
| Queries Athena/dia | ~120 (55 modelos + tests + freshness) |
| TB escaneado/mês (Athena) | ~0.5 - 1 TB |
| Invocações Lambda/mês | ~30 (apenas falhas) |

---

## Breakdown por Serviço

### S3 — Storage

| Item | Cálculo | Custo/mês |
|---|---|---|
| Free Tier | 5 GB Standard | $0 |
| Storage (acima de 5 GB) | ~20 GB × $0.023/GB | $0.46 |
| PUT requests | 1.200/mês × $0.005/1k | $0.01 |
| GET requests | 5.000/mês × $0.0004/1k | $0.00 |
| **Subtotal S3** | | **~$0.50** |

**Otimizações aplicadas**:
- Bronze após 30d → S3 IA ($0.0125/GB) economiza 45%
- Compressão Snappy reduz Parquet em ~70% vs CSV
- Particionamento Hive evita scans desnecessários

### Athena — Compute

| Item | Cálculo | Custo/mês |
|---|---|---|
| Queries | ~3.600/mês ($5/TB) | $2.50 - $5.00 |
| DDL queries | gratuitas | $0 |
| Failed queries | gratuitas | $0 |
| **Subtotal Athena** | | **~$3.00** |

**Otimizações aplicadas**:
- Iceberg metadata pruning (skip arquivos sem matching predicate)
- Partition projection elimina overhead de listing
- Modelos incrementais escaneiam apenas delta
- Compactação Iceberg (`OPTIMIZE`) mensal

### AWS Glue — Catalog

| Item | Cálculo | Custo/mês |
|---|---|---|
| Free Tier | 1M objetos/mês | $0 |
| Catálogo (atual) | ~100 tabelas | $0 |
| Glue Crawlers | NÃO usados | $0 |
| **Subtotal Glue** | | **$0.00** |

### Lambda — Slack Notifier

| Item | Cálculo | Custo/mês |
|---|---|---|
| Free Tier | 1M req + 400k GB-s | $0 |
| Invocações | ~30/mês × ~2s × 128MB | < $0.01 |
| **Subtotal Lambda** | | **$0.00** |

### SNS — Notifications

| Item | Cálculo | Custo/mês |
|---|---|---|
| Free Tier | 1M req | $0 |
| Publicações | ~30/mês | $0 |
| **Subtotal SNS** | | **$0.00** |

### Secrets Manager

| Item | Cálculo | Custo/mês |
|---|---|---|
| Secrets | 2 × $0.40 | $0.80 |
| API calls | ~100/mês (free) | $0 |
| **Subtotal Secrets Manager** | | **$0.80** |

### CloudWatch

| Item | Cálculo | Custo/mês |
|---|---|---|
| Free Tier | 5 GB logs + 3 dashboards | $0 |
| Logs (Lambda) | < 1 GB | $0 |
| Custom metrics | < 10 | $0 |
| Dashboard | 1 | $0 |
| **Subtotal CloudWatch** | | **$0.00** |

### DynamoDB (Terraform State Lock)

| Item | Cálculo | Custo/mês |
|---|---|---|
| Free Tier | 25 GB + 25 RCU/WCU | $0 |
| Uso real | <1 KB | $0 |
| **Subtotal DynamoDB** | | **$0.00** |

---

## Total Mensal

| Serviço | Free Tier | Pós Free Tier |
|---|---|---|
| S3 | $0 | $0.50 |
| Athena | $0 - $3 | $3 - $5 |
| Glue Catalog | $0 | $0 |
| Lambda | $0 | $0 |
| SNS | $0 | $0 |
| Secrets Manager | $0.80 | $0.80 |
| CloudWatch | $0 | $0 - $1 |
| DynamoDB | $0 | $0 |
| **TOTAL** | **~$1/mês** | **~$5-7/mês** |

---

## Como Reduzir Custos Adicional

### Athena
- ✅ Já implementado: partition projection, Iceberg, predicate pushdown
- Considerar: `EXPLAIN ANALYZE` em modelos lentos para identificar full scans
- Considerar: pre-aggregate em Platinum em vez de view dinâmica

### S3
- Mover Bronze após 30 dias → Glacier Instant Retrieval ($0.004/GB)
- Ativar Intelligent-Tiering em bucket Gold

### Secrets Manager
- Opção econômica: usar Parameter Store (gratuito até 10k params), trade-off: sem rotation automática

---

## Free Tier Consumido em 12 Meses (Estimativa)

| Recurso | Free Tier | Consumo Estimado | % Usado |
|---|---|---|---|
| S3 Standard | 5 GB | ~25 GB | 500% (excedido após mês 3) |
| Athena | 1 TB scan/mês | 0.5-1 TB | 50-100% |
| Lambda | 1M req | 30/mês | 0.003% |
| Glue Catalog | 1M objetos | 100 | 0.01% |
| CloudWatch | 5 GB logs | <1 GB | 20% |
| Outbound traffic | 100 GB | ~5 GB | 5% |

> **Conclusão**: serviço crítico é **S3 Standard** (excedido após mês 3 conforme volume cumula). Storage é o item mais caro ao longo do tempo, mas mesmo assim < $1/mês adicional.

---

## Cenário "Demo Permanente"

Se o projeto rodar continuamente para portfólio:

| Item | Estratégia | Custo |
|---|---|---|
| dbt build | 1x/dia agendado | $0.10/dia Athena |
| Geração dados | 1x/dia | $0.01/dia S3 PUT |
| Storage | Cumulativo (lifecycle policy) | $0.50/mês após mês 6 |

**Total estimado pós ano 1**: ~$8-12/mês (dentro de $200 créditos = ~17 meses).

---

## Cenário "Modo Pausado"

Quando NÃO em uso ativo (entre demos):

```bash
# Pausar geração + dbt
# DAGs Airflow desativadas
# Apenas storage acumulado sem queries
```

| Item | Custo/mês |
|---|---|
| S3 storage | $0.50 |
| Secrets Manager | $0.80 |
| **Total pausado** | **~$1.30/mês** |

---

## Monitoramento de Custos

Configurar **AWS Cost Anomaly Detection** + **Budget Alert**:

```hcl
# infra/modules/cost-monitoring/main.tf
resource "aws_budgets_budget" "monthly" {
  name         = "elt-pipeline-monthly"
  budget_type  = "COST"
  limit_amount = "10"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["euvhmendes@gmail.com"]
  }
}
```

---

## Tags para Cost Allocation

Todos os recursos Terraform têm tag `Project = "elt-pipeline-aws-medallion"`:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2025-04-01,End=2025-05-01 \
  --granularity MONTHLY \
  --filter '{"Tags":{"Key":"Project","Values":["elt-pipeline-aws-medallion"]}}' \
  --metrics BlendedCost
```

---

## Comparativo Solução Original vs Este Projeto

| Item | Solução Original (Azure) | Este Projeto (AWS) |
|---|---|---|
| Compute baseline | ~$300-500/mês (DBSQL Warehouse) | ~$5/mês (Athena pay-per-query) |
| Orquestração | ~$150/mês (AKS small) | $0 (Docker local) |
| EL ingestion | $300+/mês (Airbyte cloud) | $0 (gerador Python) |
| Storage | ~$50/mês (ADLS) | ~$1/mês (S3 + lifecycle) |
| **TOTAL** | **~$800/mês** | **~$6/mês** |

**Redução**: ~99% — viabilizando portfólio sem custos relevantes.

> Trade-offs: solução AWS deste projeto é dimensionada para volumes pequenos (portfólio); solução original suporta TBs/dia em produção.
