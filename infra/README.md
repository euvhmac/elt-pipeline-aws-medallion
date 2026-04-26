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
