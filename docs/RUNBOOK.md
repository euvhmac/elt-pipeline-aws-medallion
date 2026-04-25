# Runbook — Operação do Pipeline

Guia passo-a-passo para clonar, configurar, executar, e troubleshoot do projeto.

---

## Pré-Requisitos

| Ferramenta | Versão Mínima | Verificar |
|---|---|---|
| Git | 2.40+ | `git --version` |
| Docker Desktop | 20+ | `docker --version` |
| Docker Compose | v2 | `docker compose version` |
| Python | 3.11+ | `python --version` |
| Poetry | 1.7+ | `poetry --version` |
| Terraform | 1.7+ | `terraform version` |
| AWS CLI | 2.x | `aws --version` |
| GNU Make | 4+ | `make --version` |
| GitHub CLI (opcional) | 2.x | `gh --version` |

### Conta AWS

- Conta AWS com Free Tier ativo (~$200 créditos)
- IAM User com permissões: S3, Glue, Athena, IAM (criar roles), Lambda, SNS, Secrets Manager, CloudWatch
- AWS CLI configurado: `aws configure`

---

## Setup Inicial (uma vez)

### 1. Clonar Repositório

```bash
git clone https://github.com/euvhmac/elt-pipeline-aws-medallion.git
cd elt-pipeline-aws-medallion
```

### 2. Configurar Variáveis de Ambiente

```bash
cp .env.example .env
```

Editar `.env`:

```bash
# AWS
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
AWS_PROFILE=default

# S3 Buckets (gerados pelo Terraform)
S3_BRONZE=elt-pipeline-bronze-dev
S3_SILVER=elt-pipeline-silver-dev
S3_GOLD=elt-pipeline-gold-dev
S3_PLATINUM=elt-pipeline-platinum-dev
S3_ATHENA_RESULTS=elt-pipeline-athena-results-dev

# Athena
ATHENA_WORKGROUP=primary
ATHENA_DATABASE=silver

# Airflow
AIRFLOW_UID=50000
AIRFLOW_FERNET_KEY=<gerar com python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())">
```

### 3. Bootstrap Terraform Backend

Apenas na primeira vez, cria S3 + DynamoDB para state:

```bash
cd infra/bootstrap
terraform init
terraform apply -auto-approve
cd ../..
```

### 4. Provisionar Infra Dev

```bash
cd infra/envs/dev
terraform init
terraform apply
cd ../../..
```

Cria 5 buckets, 5 databases Glue, IAM roles, Secrets Manager.

### 5. Configurar Profile dbt

```bash
cp dbt/profiles_example.yml ~/.dbt/profiles.yml
# Editar com region e bucket corretos
```

Validar:
```bash
cd dbt
poetry install
poetry run dbt debug
cd ..
```

Esperado: `All checks passed!`

---

## Execução Local

### 1. Subir Stack Airflow

```bash
make up
```

Aguardar ~60s. Acessar UI em http://localhost:8080 (login: `airflow`/`airflow`).

### 2. Gerar Dados Sintéticos

```bash
make seed
```

Gera 40 arquivos Parquet (5 tenants × 8 datamarts) e faz upload para S3 Bronze.

### 3. Executar dbt Manualmente

```bash
make dbt-build
```

Equivale a `dbt build` no container Airflow.

Ou granular:
```bash
make dbt-run-silver
make dbt-run-gold
make dbt-run-platinum
make dbt-test
```

### 4. Trigger DAG Airflow

Pela UI: ativar `dag_synthetic_source` → Trigger DAG.

Pela CLI:
```bash
docker exec airflow-scheduler airflow dags trigger dag_synthetic_source
```

Acompanhar execução em http://localhost:8080/dags/dag_synthetic_source/grid

### 5. Validar Dados em Athena

```bash
aws athena start-query-execution \
  --query-string "SELECT tenant_id, COUNT(*) FROM gold.fct_vendas GROUP BY tenant_id" \
  --result-configuration OutputLocation=s3://$S3_ATHENA_RESULTS/
```

Ou via Console AWS → Athena → Query Editor.

---

## Workflow Diário

```bash
# Manhã: subir
make up

# Trabalho: editar modelos dbt
vim dbt/models/silver/silver_dw_clientes.sql
make dbt-run-silver  # validar mudança

# Antes de PR: rodar tests
make dbt-test
pre-commit run --all-files

# Final do dia
make down
```

---

## Comandos Make

| Comando | Função |
|---|---|
| `make up` | Sobe Airflow + Postgres |
| `make down` | Derruba stack (preserva volumes) |
| `make clean` | Derruba + remove volumes |
| `make seed` | Gera dados sintéticos + upload S3 |
| `make dbt-build` | Roda `dbt build` completo |
| `make dbt-run-silver` | Roda apenas modelos Silver |
| `make dbt-run-gold` | Roda apenas modelos Gold |
| `make dbt-run-platinum` | Roda apenas modelos Platinum |
| `make dbt-test` | Roda testes dbt |
| `make dbt-docs` | Gera + serve docs (porta 8090) |
| `make logs` | Tail logs Airflow |
| `make logs-scheduler` | Tail logs scheduler apenas |
| `make shell` | Bash dentro do container |
| `make tf-plan` | terraform plan dev |
| `make tf-apply` | terraform apply dev |

---

## Troubleshooting

### Airflow não inicia

```bash
docker compose logs scheduler
```

**Erros comuns**:
- `AIRFLOW_UID` não definido → checar `.env`
- Postgres não pronto → aguardar 30s, ou `make down && make up`
- Permissões em volumes → `sudo chown -R 50000:0 ./airflow/logs`

### dbt: `database not found: bronze`

Glue databases não existem. Rodar:
```bash
cd infra/envs/dev && terraform apply
```

### dbt: `AccessDenied` em S3

IAM Role do dbt não tem permissão. Verificar:
```bash
aws sts get-caller-identity
aws iam list-attached-role-policies --role-name dbt-athena-role-dev
```

### Athena: `Insufficient permissions to write to: s3://...`

Workgroup output location errado. Verificar `~/.dbt/profiles.yml`:
```yaml
s3_staging_dir: s3://elt-pipeline-athena-results-dev/
```

### dbt incremental: `Iceberg merge error`

Iceberg precisa de `unique_key` correto:
```sql
{{ config(
    incremental_strategy='merge',
    unique_key=['tenant_id', 'venda_id']  -- composite!
) }}
```

### Airflow DAG: tarefa fica em `queued`

Worker travado. Restart:
```bash
docker compose restart scheduler
```

Se persistir:
```bash
make down && make up
```

### Slack notifications não chegam

1. Verificar SNS topic existe: `aws sns list-topics`
2. Verificar Lambda subscrito: `aws sns list-subscriptions-by-topic --topic-arn <arn>`
3. Verificar Lambda logs: CloudWatch → `/aws/lambda/slack-notifier`
4. Verificar webhook URL em Secrets Manager: válido? não revogado?
5. Test manual:
   ```bash
   aws sns publish --topic-arn <arn> --message "test"
   ```

### gitleaks bloqueia commit local

```bash
# Ver o que detectou
gitleaks detect --source . --redact

# Se for falso positivo, adicionar a allowlist em .gitleaks.toml
# Nunca usar --no-verify para bypassar
```

### Athena: `Query exceeded maximum allowed memory`

Modelo está fazendo CROSS JOIN não intencional ou aggregation pesada. Soluções:
- Adicionar `WHERE tenant_id = ...` para limitar partition
- Quebrar query em CTEs intermediárias
- Materializar como `incremental` em vez de `view`
- Verificar `EXPLAIN ANALYZE <query>` no Athena

### Custos AWS subindo

```bash
# Análise rápida
aws ce get-cost-and-usage \
  --time-period Start=2025-04-01,End=2025-04-30 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

Top causas:
- Athena fazendo full table scan → adicionar partition filter
- S3 storage Bronze sem lifecycle → aplicar transição IA
- CloudWatch logs retention infinita → setar 30d

---

## Cleanup / Destroy

### Remover dados gerados (dev)

```bash
aws s3 rm s3://elt-pipeline-bronze-dev --recursive
aws s3 rm s3://elt-pipeline-silver-dev --recursive
aws s3 rm s3://elt-pipeline-gold-dev --recursive
aws s3 rm s3://elt-pipeline-platinum-dev --recursive
```

### Destruir infra dev

```bash
cd infra/envs/dev
terraform destroy
```

> **Cuidado**: buckets com versioning + objetos exigem `force_destroy = true` no Terraform.

### Reset completo (dev)

```bash
make clean                  # docker volumes
cd infra/envs/dev
terraform destroy -auto-approve
cd ../../..
rm -rf data-generator/output
```

---

## Logs e Debugging

### Logs Airflow

UI: http://localhost:8080 → DAGs → run → task → log

Container:
```bash
docker exec -it airflow-scheduler bash
tail -f /opt/airflow/logs/dag_id=dag_dbt_aws_detailed/...
```

### Logs Lambda Slack Notifier

```bash
aws logs tail /aws/lambda/slack-notifier-dev --follow
```

### Logs dbt

```bash
cd dbt
cat logs/dbt.log | tail -100
```

### Athena Query History

Console AWS → Athena → Recent queries
Ou via CLI:
```bash
aws athena list-query-executions --max-items 10
aws athena get-query-execution --query-execution-id <id>
```

---

## Operações de Manutenção

### Compactar Iceberg tables (Sprint 6+)

```sql
OPTIMIZE silver.silver_dw_venda REWRITE DATA USING BIN_PACK;
VACUUM silver.silver_dw_venda;
```

### Recompactar partições antigas

```bash
# Cron mensal recomendado
make iceberg-optimize
```

### Atualizar Glue partitions (caso partition projection falhe)

```bash
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE bronze.vendas"
```

### Backup manifest dbt

```bash
aws s3 sync dbt/target/ s3://elt-pipeline-dbt-artifacts-dev/$(date +%Y-%m-%d)/
```

---

## Smoke Test (após qualquer mudança grande)

```bash
make down && make clean
make up
make seed
make dbt-build
make dbt-test
```

Deve completar em < 30 min sem erros.
