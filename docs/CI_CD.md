# CI/CD — GitHub Actions

Pipeline de qualidade que bloqueia merges com problemas. Três workflows independentes + pre-commit hooks.

## Visão Geral

```
┌─────────────────────────────────────────────┐
│            Developer Workflow               │
└─────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│  Local (pre-commit hooks):                  │
│  • sqlfluff lint                            │
│  • dbt-checkpoint                           │
│  • terraform fmt                            │
│  • gitleaks (light)                         │
└─────────────────────────────────────────────┘
                      │
                      ▼
                  git push
                      │
                      ▼
            Pull Request opens
                      │
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
┌──────────┐   ┌──────────┐   ┌──────────┐
│ secrets- │   │ dbt-ci   │   │terraform │
│  scan    │   │          │   │  -ci     │
└──────────┘   └──────────┘   └──────────┘
        │             │             │
        └─────────────┼─────────────┘
                      ▼
              Branch Protection
              (require all checks)
                      │
                      ▼
                Merge to main
```

---

## Workflow 1 — `secrets-scan.yml`

Roda em todos os PRs. Bloqueia merge se encontrar secrets.

```yaml
# .github/workflows/secrets-scan.yml
name: secrets-scan

on:
  pull_request:
  push:
    branches: [main]

jobs:
  gitleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Run gitleaks
        uses: gitleaks/gitleaks-action@v2
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GITLEAKS_CONFIG: .gitleaks.toml
```

`.gitleaks.toml` customizado para detectar:
- AWS keys (`AKIA*`)
- Slack webhooks (`hooks.slack.com/services/...`)
- Tokens genéricos com alta entropia
- Padrões corporativos do projeto baseline (allowlist se necessário)

---

## Workflow 2 — `dbt-ci.yml`

Roda quando arquivos `dbt/**` mudam.

```yaml
# .github/workflows/dbt-ci.yml
name: dbt-ci

on:
  pull_request:
    paths:
      - 'dbt/**'
      - '.github/workflows/dbt-ci.yml'

env:
  AWS_REGION: us-east-1
  DBT_PROFILES_DIR: ./dbt

jobs:
  dbt-build:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'
          cache: 'pip'
      
      - name: Install dbt
        working-directory: ./dbt
        run: |
          pip install dbt-core dbt-athena-community
          dbt deps
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GHA_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Download production manifest
        run: |
          aws s3 cp s3://elt-pipeline-dbt-artifacts-prd/manifest.json ./dbt/state/
      
      - name: dbt parse
        working-directory: ./dbt
        run: dbt parse --target ci
      
      - name: dbt build (modified+)
        working-directory: ./dbt
        run: |
          dbt build \
            --select state:modified+ \
            --defer \
            --state ./state \
            --target ci \
            --fail-fast
      
      - name: dbt source freshness
        working-directory: ./dbt
        run: dbt source freshness --target ci
        continue-on-error: true
      
      - name: Upload artifacts
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: dbt-artifacts-${{ github.sha }}
          path: dbt/target/
```

### Estratégia "modified+"

`state:modified+` constrói apenas modelos alterados **e seus descendentes downstream**. Combinado com `--defer`, modelos upstream não-alterados leem do schema de produção, evitando rebuild desnecessário.

**Ganho**: PR que altera 1 modelo Silver roda 5-10 modelos em vez de 55.

### CI Target em `profiles.yml`

```yaml
default:
  target: dev
  outputs:
    dev:
      type: athena
      schema: dbt_dev
      ...
    ci:
      type: athena
      schema: dbt_ci_{{ env_var('GITHUB_PR_NUMBER', 'unknown') }}
      threads: 4
      ...
```

PR isolado: `dbt_ci_42` para PR #42. Cleanup pós-merge via cron.

---

## Workflow 3 — `terraform-ci.yml`

Roda quando arquivos `infra/**` mudam.

```yaml
# .github/workflows/terraform-ci.yml
name: terraform-ci

on:
  pull_request:
    paths:
      - 'infra/**'
      - '.github/workflows/terraform-ci.yml'

env:
  TF_VERSION: 1.7.5
  AWS_REGION: us-east-1

jobs:
  validate:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    
    strategy:
      matrix:
        env: [dev, prd]
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}
      
      - name: Terraform fmt check
        run: terraform fmt -check -recursive
        working-directory: ./infra
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GHA_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      
      - name: Terraform Init
        working-directory: ./infra/envs/${{ matrix.env }}
        run: terraform init
      
      - name: Terraform Validate
        working-directory: ./infra/envs/${{ matrix.env }}
        run: terraform validate
      
      - name: tfsec
        uses: aquasecurity/tfsec-action@v1.0.3
        with:
          working_directory: ./infra
      
      - name: checkov
        uses: bridgecrewio/checkov-action@master
        with:
          directory: ./infra
          framework: terraform
      
      - name: Terraform Plan
        id: plan
        if: matrix.env == 'dev'
        working-directory: ./infra/envs/${{ matrix.env }}
        run: terraform plan -no-color -out=tfplan
        continue-on-error: true
      
      - name: Comment Plan on PR
        if: matrix.env == 'dev'
        uses: actions/github-script@v7
        with:
          script: |
            const output = `#### Terraform Plan (${{ matrix.env }})
            <details><summary>Show plan</summary>
            \`\`\`
            ${{ steps.plan.outputs.stdout }}
            \`\`\`
            </details>`
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: output
            })
```

### OIDC com AWS

Usa OpenID Connect — sem credenciais AWS no GitHub. Configuração:
1. Trust relationship em IAM Role permitindo `token.actions.githubusercontent.com`
2. Role ARN exposto via `secrets.AWS_GHA_ROLE_ARN`
3. Permissões mínimas (read S3 state + read AWS resources)

---

## Workflow 4 (futuro) — `dbt-deploy.yml`

Após merge em `main`, deploy para produção:

```yaml
# .github/workflows/dbt-deploy.yml (Sprint 8+)
name: dbt-deploy

on:
  push:
    branches: [main]
    paths: ['dbt/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Airflow DAG
        run: |
          curl -X POST $AIRFLOW_URL/api/v1/dags/dag_dbt_aws_detailed/dagRuns \
            -H "Authorization: Bearer $AIRFLOW_TOKEN"
      
      - name: Upload manifest to S3 (production state)
        run: |
          aws s3 cp dbt/target/manifest.json \
            s3://elt-pipeline-dbt-artifacts-prd/manifest.json
```

---

## Pre-Commit Hooks

`.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/sqlfluff/sqlfluff
    rev: 3.0.0
    hooks:
      - id: sqlfluff-lint
        files: ^dbt/models/.*\.sql$
        args: [--dialect, athena]
  
  - repo: https://github.com/dbt-checkpoint/dbt-checkpoint
    rev: v2.0.0
    hooks:
      - id: check-model-has-properties-file
        files: ^dbt/models/(silver|gold)/.*\.sql$
      - id: check-source-has-tests
      - id: check-model-has-description
        files: ^dbt/models/gold/.*\.sql$
  
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.86.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_tfsec
  
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

Setup:
```bash
pip install pre-commit
pre-commit install
```

---

## Branch Protection (main)

Configuração em `Settings → Branches → main`:

- ✅ Require pull request before merging
- ✅ Require approvals (1)
- ✅ Dismiss stale reviews
- ✅ Require status checks to pass:
  - `secrets-scan / gitleaks`
  - `dbt-ci / dbt-build`
  - `terraform-ci / validate (dev)`
  - `terraform-ci / validate (prd)`
- ✅ Require branches to be up to date
- ✅ Do not allow bypassing
- ✅ Restrict force pushes

---

## Secrets do Repo

Configurar em `Settings → Secrets and variables → Actions`:

| Secret | Uso |
|---|---|
| `AWS_GHA_ROLE_ARN` | OIDC para AWS |
| `AIRFLOW_URL` | Webhook Airflow (futuro) |
| `AIRFLOW_TOKEN` | Auth Airflow API (futuro) |
| `SLACK_WEBHOOK_URL` | (apenas para testes) |

---

## Métricas de CI

| Métrica | Meta |
|---|---|
| Tempo médio CI total | < 5 min |
| Tempo dbt-ci (cache hit) | < 3 min |
| Tempo terraform-ci | < 2 min |
| Falsos positivos (gitleaks) | 0 |
| % PRs bloqueados por quality gate | 5-15% (saudável) |

---

## Renovate / Dependabot

Configurar `.github/dependabot.yml`:

```yaml
version: 2
updates:
  - package-ecosystem: pip
    directory: /dbt
    schedule:
      interval: weekly
  
  - package-ecosystem: pip
    directory: /data-generator
    schedule:
      interval: weekly
  
  - package-ecosystem: terraform
    directory: /infra
    schedule:
      interval: weekly
  
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```
