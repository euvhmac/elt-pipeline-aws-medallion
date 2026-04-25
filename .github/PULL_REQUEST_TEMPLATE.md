<!--
Title obrigatório seguindo Conventional Commits PT-BR:
  <tipo>(<escopo>): <descrição>
Exemplo: feat(dbt): adiciona modelo fct_devolucao com merge incremental
-->

## 📝 Descrição

<!-- O que este PR muda e por quê. Seja explícito sobre motivação e contexto. -->

## 🔗 Issues / ADRs Relacionados

<!-- Closes #N | Refs #N | ADR-NNNN -->
- Closes #
- Refs ADR-

## 🧩 Componentes Afetados

- [ ] dbt (`dbt/models/**`)
- [ ] Airflow (`airflow/dags/**`)
- [ ] Data Generator (`data-generator/**`)
- [ ] Terraform / Infra (`infra/**`)
- [ ] Lambda (`lambda/**`)
- [ ] CI/CD (`.github/workflows/**`)
- [ ] Documentação (`docs/**`, `README.md`)
- [ ] `.github/` (instructions, templates)
- [ ] Seeds (`dbt/seeds/**`)
- [ ] Outro: ___

## 🎯 Camada Medallion Afetada

- [ ] Bronze
- [ ] Silver
- [ ] Gold (dims/facts)
- [ ] Gold (DRE)
- [ ] Platinum
- [ ] N/A (não dbt)

## ✅ Como Foi Testado

<!-- Comandos executados, screenshots, output relevante. -->

```bash
# Exemplo
dbt build --select fct_devolucao+
pytest tests/unit/ -v
terraform plan -out=tfplan
```

**Output / Evidência**:
<!-- cole logs, screenshots, ou link para CI run -->

## 💰 Impacto de Custo AWS

<!-- Obrigatório se PR adiciona/modifica recursos AWS. -->

| Recurso | Custo estimado/mês |
|---|---|
| | |

**Mitigações aplicadas**:
- [ ] Athena workgroup com `bytes_scanned_cutoff`
- [ ] S3 lifecycle policy
- [ ] CloudWatch retention configurado
- [ ] Lambda right-sized (arm64, mem mínima)
- [ ] N/A (sem mudança AWS)

**EXPLAIN ANALYZE** (se modelo Gold/Platinum complexo):
<details>
<summary>Plano de execução</summary>

```
-- output do EXPLAIN ANALYZE
```

</details>

## ✅ Checklist Tech Lead

### Geral
- [ ] Title segue Conventional Commits PT-BR
- [ ] Branch atualizada com `main`
- [ ] PR pequeno (< 400 linhas) ou quebra justificada
- [ ] Documentação atualizada (`docs/`, `README.md`) quando aplicável
- [ ] ADR criado se houver decisão arquitetural ([template](.github/ISSUE_TEMPLATE/adr_proposal.yml))

### Qualidade de Código
- [ ] Pre-commit hooks passaram (`sqlfluff`, `ruff`, `terraform fmt`, `gitleaks`)
- [ ] Testes adicionados/atualizados ([testing.instructions.md](.github/instructions/testing.instructions.md))
- [ ] CI verde (secrets-scan + dbt-ci/terraform-ci aplicáveis)
- [ ] Cobertura mínima respeitada (70% Python, 100% PKs/FKs Gold)

### Multi-Tenant
- [ ] `tenant_id` presente em queries/tabelas novas
- [ ] Surrogate keys são compostas com `tenant_id`
- [ ] Partition pruning em queries Athena

### Segurança ([security.instructions.md](.github/instructions/security.instructions.md))
- [ ] Sem secrets hardcoded
- [ ] `.env` não está no commit
- [ ] IAM policies sem `Action: "*"` ou `Resource: "*"` sem condition
- [ ] S3 buckets com block public access + encryption
- [ ] Logs não expõem PII / secrets

### Observabilidade ([observability.instructions.md](.github/instructions/observability.instructions.md))
- [ ] Logs estruturados JSON
- [ ] DAGs com `on_failure_callback`
- [ ] Métricas críticas emitidas (se aplicável)

### Custo ([cost-awareness.instructions.md](.github/instructions/cost-awareness.instructions.md))
- [ ] Athena: `WHERE tenant_id` + filtro de data
- [ ] Não usa `SELECT *` em Gold/Platinum
- [ ] Sem cross join não-intencional
- [ ] S3 lifecycle policy (se novo bucket)

## ⚠️ Breaking Changes

- [ ] Sem breaking changes
- [ ] Com breaking changes (descrever migração abaixo)

<!-- Se BC: descrever como consumidores devem migrar. Adicionar `BREAKING CHANGE:` no commit footer. -->

## 📸 Screenshots / Lineage / Diagramas

<!-- Quando aplicável: dbt docs, lineage, dashboards CloudWatch, etc. -->

## 🤝 Co-authors (Pair Extraordinaire 👥)

<!-- Se trabalhou pareado. Achievement opportunity. -->

```
Co-authored-by: Nome <email>
```

## 🦈 Notas para Reviewer

<!-- Áreas que requerem atenção especial, decisões trade-off, contexto adicional. -->

---

<!--
🦈 Achievement Opportunity: ao mergear este PR você farma Pull Shark.
🤪 Self-merge sem review = YOLO (em projeto solo).
🔫 PR aberto e fechado em < 5 min = Quickdraw.
-->
