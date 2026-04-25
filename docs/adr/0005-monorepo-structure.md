# ADR-0005 — Monorepo vs Multi-Repo

- **Status**: Accepted
- **Data**: 2025-04-25
- **Decisores**: Vhmac (autor)

---

## Contexto

O projeto envolve 4 componentes principais:
1. **dbt project** (modelos SQL)
2. **Airflow DAGs** (orquestração)
3. **Data generator** (Python ingestão)
4. **Terraform IaC** (infra AWS)

A solução original mantinha cada um em repositório separado (ou em monorepos diferentes). Para o portfólio público, decidir:

1. **Monorepo único** com todos os componentes
2. **Multi-repo** (4 repos separados, conectados via submodules ou doc cross-refs)
3. **Híbrido** (componentes sensíveis em repos privados, outros em monorepo)

Critérios:
- Visibilidade de fluxo end-to-end
- Reviewability em PRs
- Complexidade de CI/CD
- Onboarding de visitantes (recrutadores)
- Versionamento e releases

---

## Decisão

**Adotar monorepo único** (`elt-pipeline-aws-medallion`) contendo dbt, Airflow, gerador de dados, Terraform e documentação.

---

## Justificativa

### Por que monorepo é melhor para este projeto

1. **Narrativa única em portfolio**:
   - Um único repo demonstra projeto completo
   - Recrutador clica em 1 link e vê arquitetura inteira
   - Multi-repo dilui atenção

2. **Reviewability cross-component**:
   - PR que muda schema dbt + DAG Airflow + Terraform fica em 1 PR
   - Reviewer vê o impacto end-to-end de uma feature
   - Evita "PR aprovado em repo X quebra repo Y"

3. **CI/CD simplificado**:
   - Workflows compartilham `.github/workflows/`
   - State entre workflows é trivial (`dbt-ci` lê `data-generator/output/` para tests)
   - Multi-repo exigiria orchestration externa (CodePipeline, Argo Events)

4. **Versionamento atômico**:
   - 1 commit captura mudança coordenada em todos os componentes
   - Rollback é simples (`git revert`)
   - Multi-repo: versioning matrix complica matrix de compatibilidade

5. **Onboarding**:
   - `git clone` único + `make up` → ambiente completo
   - Multi-repo: clonar 4 repos + configurar inter-dependencies

6. **Documentação centralizada**:
   - `docs/` cobre projeto inteiro com cross-links
   - Multi-repo: README de cada um precisa redocumentar contexto

### Limitações aceitas

1. **Não escala para times grandes**:
   - Para 50+ engenheiros tocando componentes independentes, multi-repo é melhor
   - Para projeto single-author, monorepo vence

2. **CI pode ficar lento**:
   - Mitigação: `paths:` filter por workflow (dbt-ci só roda se `dbt/**` mudar)

3. **Tamanho do repo cresce**:
   - Mitigação: artifacts (logs, target/, output/) em `.gitignore`

4. **Deploy independente é mais complexo**:
   - Para este projeto: deploys coordenados são na verdade desejados

---

## Comparação Detalhada

| Critério | Monorepo | Multi-Repo |
|---|---|---|
| Onboarding (1 dev) | ✅ 1 clone | ❌ 4 clones |
| Cross-component PRs | ✅ 1 PR | ❌ N PRs sincronizados |
| CI/CD setup | ✅ Compartilhado | ⚠️ Replicado em cada |
| Deploys independentes | ⚠️ Possível com paths filter | ✅ Native |
| Escala (time grande) | ❌ Conflitos | ✅ Ownership clara |
| Narrativa portfolio | ✅✅ End-to-end visível | ❌ Fragmentada |
| Tamanho repo | ⚠️ Maior | ✅ Pequeno |
| Tools (Bazel, Nx) | ⚠️ Necessário em escala | ✅ Não necessário |

---

## Estrutura do Monorepo

```
elt-pipeline-aws-medallion/
├── README.md                    # Hero do projeto
├── LICENSE                      # MIT
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── Makefile                     # Atalhos UX
├── .env.example
├── .gitignore
├── .gitleaks.toml
├── .pre-commit-config.yaml
├── .sqlfluff
├── pyproject.toml               # Workspace Poetry
│
├── docs/                        # Documentação central
│   ├── README.md
│   ├── PROJECT_BLUEPRINT.md
│   ├── ARCHITECTURE_AWS.md
│   ├── MIGRATION_FROM_AZURE.md
│   ├── SPRINT_ROADMAP.md
│   ├── TECHNOLOGIES.md
│   ├── DATA_MODEL.md
│   ├── SOURCE_DATA_GENERATOR.md
│   ├── MEDALLION_LAYERS.md
│   ├── CI_CD.md
│   ├── RUNBOOK.md
│   ├── COST_ESTIMATE.md
│   ├── INTERVIEW_NARRATIVE.md
│   └── adr/
│       ├── 0001-iceberg-vs-delta.md
│       ├── 0002-athena-vs-emr.md
│       ├── 0003-airflow-local-vs-mwaa.md
│       ├── 0004-synthetic-data.md
│       └── 0005-monorepo-structure.md
│
├── dbt/                         # dbt project
│   ├── dbt_project.yml
│   ├── packages.yml
│   ├── profiles_example.yml
│   ├── macros/
│   ├── models/
│   │   ├── silver/
│   │   ├── gold/
│   │   └── platinum/
│   ├── seeds/
│   └── tests/
│
├── airflow/                     # Orquestração
│   ├── docker-compose.yml
│   ├── Dockerfile (custom image)
│   ├── dags/
│   │   ├── dag_synthetic_source.py
│   │   ├── dag_dbt_aws_detailed.py
│   │   └── utils/
│   │       ├── callbacks.py
│   │       └── slack.py
│   ├── plugins/
│   └── airflow_settings.yaml
│
├── data-generator/              # Gerador Python
│   ├── pyproject.toml
│   ├── src/
│   │   ├── schemas/
│   │   ├── generators/
│   │   ├── writers/
│   │   ├── config.py
│   │   └── main.py
│   └── tests/
│
├── infra/                       # Terraform
│   ├── bootstrap/
│   ├── modules/
│   │   ├── s3-medallion/
│   │   ├── glue-catalog/
│   │   ├── iam-roles/
│   │   ├── secrets-manager/
│   │   ├── athena/
│   │   ├── sns-lambda/
│   │   └── cost-monitoring/
│   └── envs/
│       ├── dev/
│       └── prd/
│
└── .github/
    ├── workflows/
    │   ├── secrets-scan.yml
    │   ├── dbt-ci.yml
    │   └── terraform-ci.yml
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE.md
```

---

## CI Path Filtering

Cada workflow só dispara quando seu domínio muda:

```yaml
# .github/workflows/dbt-ci.yml
on:
  pull_request:
    paths:
      - 'dbt/**'
      - '.github/workflows/dbt-ci.yml'

# .github/workflows/terraform-ci.yml
on:
  pull_request:
    paths:
      - 'infra/**'
      - '.github/workflows/terraform-ci.yml'

# .github/workflows/data-generator-ci.yml (futuro)
on:
  pull_request:
    paths:
      - 'data-generator/**'
```

Resultado: PR alterando só dbt não dispara terraform-ci (zero waste).

---

## Versioning

Tags Git seguem **CalVer**: `YYYY.MM.PATCH`
- `2025.04.0` — primeira release Sprint 0
- `2025.05.0` — Sprint 1 completa
- `2025.06.1` — Hotfix Sprint 5

Cada release contém **changelog cobrindo todos os componentes**.

---

## Consequências

### Positivas

- ✅ Visitor experience: 1 link explica tudo
- ✅ Setup: `git clone && make up`
- ✅ PRs cross-component são naturais
- ✅ Documentação centralizada
- ✅ Versioning atômico simplifica rollbacks

### Negativas

- ⚠️ Repo cresce com tempo (mitigar com artifacts ignorados)
- ⚠️ Tooling não-monorepo-aware (Renovate, Dependabot) precisa configuração de paths
- ⚠️ CI matrix mais complexa (path filters)

### Mitigações

- `.gitignore` agressivo com tudo que não é source code
- Renovate configurado com `packageManagers` separados por path
- Workflow names claros incluem componente: `dbt-ci`, `terraform-ci`

---

## Alternativas Consideradas

### Alternativa 1: 4 repos separados
- ❌ Onboarding ruim (clonar 4)
- ❌ PR cross-component complexo
- ❌ Documentação fragmentada
- ✅ Ownership clara (irrelevante para 1 dev)

### Alternativa 2: Submodules
- ❌ UX ruim do git submodule
- ❌ Versioning matrix complica
- ❌ Não resolve o problema de visibilidade

### Alternativa 3: Híbrido (privado + público)
- ❌ Defeats purpose do portfolio (parte fica oculta)
- ❌ Confusão de qual é fonte oficial

### Alternativa 4: Monorepo com Bazel/Nx
- ❌ Overengineering para projeto single-dev
- ❌ Curva de aprendizado adiciona complexidade sem ganho
- ✅ Reconsiderar se projeto crescer 10x

---

## Caminho de Upgrade

Se time crescer ou projeto bifurcar em produtos diferentes:

```
Monorepo (atual)
    │
    ▼
Monorepo + Bazel/Nx (10+ devs)
    │
    ▼
Bifurcar: dbt-project (próprio repo) + airflow (próprio repo) + terraform-modules (próprio repo)
```

Mas isso é Phase 3+, não no horizonte deste portfolio.

---

## Referências

- [Monorepo vs Polyrepo](https://monorepo.tools/)
- [Google's Monolithic Repo (Bazel origin)](https://research.google/pubs/pub45424/)
- [Microsoft's Engineering Fundamentals — Repo Strategy](https://microsoft.github.io/code-with-engineering-playbook/)

---

## Revisão

Reavaliar se:
- Time crescer para 5+ devs
- Componentes precisarem release independente com SLA
- CI total ficar > 15 min mesmo com path filters
