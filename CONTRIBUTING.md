# Contribuindo

Obrigado pelo interesse em contribuir!

## Processo de Contribuição

1. **Fork** o repositório
2. **Branch** a partir de `main`: `git checkout -b feature/minha-feature`
3. **Commit** seguindo [Conventional Commits em PT-BR](#conventional-commits)
4. **Push** para o seu fork: `git push origin feature/minha-feature`
5. **Pull Request** para `main` deste repositório

## Pré-requisitos

- Pre-commit hooks instalados: `pre-commit install`
- Python 3.11+
- Docker Desktop
- AWS CLI configurado (para PRs que envolvem infra)

## Padrões

### Conventional Commits

Mensagens de commit seguem [Conventional Commits](https://www.conventionalcommits.org/) em **português brasileiro**:

```
<tipo>(<escopo>): <descrição curta>

[corpo opcional]

[footer opcional]
```

**Tipos válidos**:
- `feat`: nova feature
- `fix`: correção de bug
- `docs`: documentação
- `refactor`: refactor sem mudança funcional
- `test`: adicionar/ajustar testes
- `chore`: tarefas de build/CI
- `perf`: melhoria de performance

**Exemplos**:
```
feat(dbt): adiciona modelo fct_devolucao
fix(airflow): corrige callback Slack quando task falha
docs(adr): adiciona ADR-0006 sobre OpenLineage
```

### Code Style

- **SQL**: SQLFluff dialect `athena`. Rode `sqlfluff lint dbt/models/`
- **Python**: ruff + black. Rode `ruff check . && black .`
- **Terraform**: `terraform fmt -recursive`
- **YAML**: indent 2 espaços

### Testes

PRs que adicionam/alteram código devem incluir testes:
- **dbt models**: schema tests + relationships
- **Python**: pytest (data-generator/, airflow/dags/utils/)
- **Terraform**: tfsec + checkov passam

## Quality Gates

Todo PR passa por:
- ✅ `secrets-scan` (gitleaks)
- ✅ `dbt-ci` (se altera `dbt/**`)
- ✅ `terraform-ci` (se altera `infra/**`)
- ✅ Pre-commit hooks
- ✅ Review de pelo menos 1 mantenedor

## Estrutura do PR

Use o template `.github/PULL_REQUEST_TEMPLATE.md`. Inclua:
- Descrição da mudança
- Motivação / contexto
- Testes realizados
- Screenshots (se UI)
- Checklist

## Reportando Bugs

Use o template em `.github/ISSUE_TEMPLATE/bug_report.md`.

## Sugerindo Features

Use o template `.github/ISSUE_TEMPLATE/feature_request.md`.

## Decisões Arquiteturais

Mudanças arquiteturais significativas exigem **ADR** em `docs/adr/`. Use o template Michael Nygard:
- Status, Data, Decisores
- Contexto
- Decisão
- Justificativa
- Consequências
- Alternativas Consideradas

## Comunicação

- Issues: discussões técnicas
- Discussions: perguntas gerais
- PRs: code review

## Code of Conduct

Veja [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
