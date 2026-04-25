# ADR-0002 — Athena vs EMR Serverless vs Redshift

- **Status**: Accepted
- **Data**: 2025-04-25
- **Decisores**: Vhmac (autor)

---

## Contexto

A migração precisa de uma engine SQL para executar transformações dbt sobre dados em S3 + Iceberg. As opções principais na AWS:

1. **Amazon Athena** (engine v3 / Trino)
2. **Amazon EMR Serverless** (Spark)
3. **Amazon EMR on EC2** (Spark cluster gerenciado)
4. **Amazon Redshift Serverless / RA3**

Critérios:
- Custo (especialmente em modo idle)
- Performance para volume estimado (< 1 TB/dia processado)
- Suporte a Iceberg
- Compatibilidade com dbt
- Latência de cold start

---

## Decisão

**Adotar Amazon Athena (engine v3)** como engine SQL única para todas as queries dbt.

---

## Justificativa

### Por que Athena ganha para este caso de uso

1. **Custo zero idle**:
   - Pay-per-query: $5/TB scanned
   - Sem cluster ligado consumindo recursos
   - Para portfólio (uso intermitente), modelo ideal

2. **Volume cabe folgado**:
   - ~1 TB/mês escaneado estimado
   - Custo: ~$5/mês
   - EMR Serverless mínimo: ~$30/mês (1 DPU ligada por job)

3. **Iceberg first-class**:
   - Engine v3 = Trino, com suporte SQL standard a Iceberg
   - MERGE, time travel, schema evolution funcionam
   - dbt-athena adapter maduro

4. **Zero ops**:
   - Sem cluster para gerenciar, escalar, ou patch
   - Sem decisões sobre tipo de instância, autoscaling

5. **Integração nativa**:
   - Glue Catalog é o catálogo padrão
   - Resultados em S3 sem config extra
   - Workgroups para isolamento dev/prd

6. **Limites suficientes**:
   - 30 min/query (mais que suficiente para nossos modelos)
   - 100 DPU concorrentes default (escalável on-demand)

### Limitações aceitas

1. **Cold start ~3-5s** por query
   - Aceitável para batch jobs
   - Não aceitável para queries sub-segundo (não é nosso caso)

2. **Sem job scheduling interno**
   - Precisamos de Airflow externamente (já planejado)

3. **Spark features não disponíveis**:
   - Sem ML libraries integradas (não precisamos)
   - Sem streaming (não precisamos hoje)

4. **Pricing por TB scanned pode crescer**:
   - Se volume crescer 100x → considerar EMR
   - Mitigação: partition pruning + Iceberg metadata

---

## Comparação Detalhada

| Critério | Athena | EMR Serverless | EMR on EC2 | Redshift |
|---|---|---|---|---|
| Custo idle | $0 | $0 | ~$100+/mês | ~$200+/mês |
| Custo por uso | $5/TB | ~$0.50-2/hour DPU | ~$0.10/hour/node | ~$0.36/hour |
| Cold start | 3-5s | 60-120s | 0 (sempre on) | 0 (sempre on) |
| Iceberg | ✅ Engine v3 | ✅ Spark + Iceberg | ✅ Spark + Iceberg | ⚠️ Spectrum |
| dbt support | ✅ dbt-athena | ✅ dbt-spark | ✅ dbt-spark | ✅ dbt-redshift |
| Setup complexity | Mínimo | Médio | Alto | Médio |
| ML/Streaming | ❌ | ✅ | ✅ | ⚠️ Limited |
| Adequado para escala | ~10 TB/mês | 10-100 TB/mês | 100+ TB/mês | 1-100 TB |

---

## Consequências

### Positivas

- ✅ Custo total ~$5-7/mês confirmado em [COST_ESTIMATE.md](../COST_ESTIMATE.md)
- ✅ Setup time < 30 min (workgroup + IAM role)
- ✅ Pipeline funciona idle a $0/mês quando não em uso
- ✅ Sem decisões de capacidade/instância

### Negativas

- ⚠️ Custo por TB scanned cresce linearmente — vigiar volume
- ⚠️ Cold start de 3-5s não permite queries interativas em dashboards
- ⚠️ Limit 30 min/query pode ser problema se modelo Platinum complexo

### Mitigações

- Custo: partition projection + Iceberg metadata pruning + view pre-aggregations
- Cold start: aceitar (estamos batch)
- Timeout: dividir Platinum em CTEs/intermediários, materializar como `table` se necessário

---

## Alternativas Consideradas

### Alternativa 1: EMR Serverless
**Por que rejeitada**: $30+/mês mínimo, cold start maior (60s+), complexidade adicional Spark sem ganho real.

**Quando reconsiderar**: se volume passar 10 TB/mês ou se precisarmos Spark UDFs/ML.

### Alternativa 2: Redshift Serverless
**Por que rejeitada**: $0.36/hour mínimo (~$260/mês idle 24/7), e Iceberg via Redshift Spectrum tem features limitadas comparado a Athena nativo.

**Quando reconsiderar**: se precisar BI analítico interativo (latência sub-segundo) e volume ≥ 5 TB.

### Alternativa 3: Snowflake
**Por que rejeitada**: fora do escopo (multi-cloud, e foco do projeto é AWS); custos similares ao Redshift; lock-in.

### Alternativa 4: Self-hosted Trino on EC2/EKS
**Por que rejeitada**: complexidade operacional alta; sem benefício de custo vs Athena para volumes pequenos; defeats purpose do "managed" da escolha AWS.

---

## Decisão de Fronteira (Athena vs EMR)

| Volume mensal escaneado | Engine recomendada |
|---|---|
| < 5 TB | Athena (este projeto) |
| 5 - 50 TB | Athena com FastSlot ou EMR Serverless |
| > 50 TB | EMR Serverless ou EMR on EC2 |

Para portfólio (volume sintético estimado em < 1 TB/mês), Athena é a escolha óbvia.

---

## Workgroup Strategy

```hcl
# infra/modules/athena/main.tf
resource "aws_athena_workgroup" "primary" {
  name = "elt-pipeline-${var.env}"
  
  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    
    result_configuration {
      output_location = "s3://${var.athena_results_bucket}/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
    
    bytes_scanned_cutoff_per_query = 10737418240  # 10 GB cutoff
  }
}
```

`bytes_scanned_cutoff_per_query` previne queries acidentais > 10 GB (proteção de custo).

---

## Referências

- [AWS Athena Pricing](https://aws.amazon.com/athena/pricing/)
- [AWS EMR Serverless Pricing](https://aws.amazon.com/emr/serverless/pricing/)
- [Athena Engine v3 (Trino) Release Notes](https://docs.aws.amazon.com/athena/latest/ug/engine-versions-reference-0003.html)
- [dbt-athena](https://github.com/dbt-athena/dbt-athena)

---

## Revisão

Reavaliar se:
- Volume escaneado > 10 TB/mês por 3 meses consecutivos
- dbt build > 30 min
- Necessidade de ML, streaming, ou SQL interativo (sub-segundo)
