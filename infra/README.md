# infra/

Infrastructure as Code (Terraform) para o pipeline.

## Estrutura

```
infra/
├── modules/
│   ├── s3-medallion/      # 5 buckets (bronze/silver/gold/platinum/athena-results)
│   ├── glue-catalog/      # 5 databases Glue
│   ├── iam-roles/         # User dbt-athena + Role lambda-slack
│   ├── secrets-manager/   # Slack webhook placeholder
│   └── athena-workgroup/  # Workgroup com bytes_scanned_cutoff
└── envs/
    └── dev/               # Composicao para ambiente dev
```

## Bootstrap (uma unica vez, fora do Terraform)

```powershell
$ACCOUNT=(aws sts get-caller-identity --query Account --output text)
$BUCKET="elt-pipeline-tfstate-$ACCOUNT"
$TABLE="elt-pipeline-tfstate-lock"
aws s3api create-bucket --bucket $BUCKET --region us-east-1
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket $BUCKET --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws dynamodb create-table --table-name $TABLE --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1
```

## Uso

```powershell
cd infra/envs/dev
terraform init
terraform plan
terraform apply
```

Destruir tudo: `terraform destroy`.

## Custo estimado (dev, recursos vazios)

| Recurso | Custo/mes |
|---|---|
| 5 S3 buckets vazios | $0 |
| 5 Glue databases | $0 |
| 1 IAM user + policy | $0 |
| 1 Secret Manager | $0.40 |
| 1 Athena workgroup | $0 |
| Backend (S3 + DynamoDB) | ~$0.02 |
| **Total** | **~$0.42** |
# Infra (Terraform) — Skeleton

Estrutura será preenchida na **Sprint 2**.

## Estrutura prevista

```
infra/
├── modules/
│   ├── s3-medallion/
│   ├── glue-catalog/
│   ├── iam-roles/
│   ├── secrets-manager/
│   └── sns-lambda/
└── envs/
    ├── dev/
    │   ├── main.tf
    │   ├── variables.tf
    │   ├── terraform.tfvars     # gitignored
    │   └── versions.tf
    └── prd/
```

## Backend remoto (bootstrap manual antes de Sprint 2)

- S3: `elt-pipeline-tfstate-${aws_account_id}`
- DynamoDB lock: `elt-pipeline-tfstate-lock`
