---
applyTo: '**'
---

# Copilot Instructions — elt-pipeline-aws-medallion

> Instruções foundational sempre carregadas. Define contexto, princípios e anti-patterns para todo desenvolvimento neste repositório.

---

## Contexto do Projeto

**Nome**: `elt-pipeline-aws-medallion`
**Tipo**: Plataforma analítica multi-tenant em AWS com arquitetura Medallion
**Status**: Recriação para portfólio público de uma plataforma corporativa interna (acesso original sob NDA)
**Autor**: Vhmac (`euvhmac` no GitHub, `euvhmendes@gmail.com`)

### Stack Principal

- **Storage**: Amazon S3 + Apache Iceberg
- **Engine SQL**: Amazon Athena (engine v3 / Trino)
- **Catálogo**: AWS Glue Data Catalog
- **Transformação**: dbt-core + dbt-athena-community
- **Orquestração**: Apache Airflow 2.9 (Docker Compose local)
- **Ingestão**: Gerador Python sintético (Faker + PyArrow)
- **IaC**: Terraform 1.7+
- **CI/CD**: GitHub Actions
- **Observabilidade**: SNS + Lambda + CloudWatch

### Arquitetura

Medallion 4-camadas: **Bronze → Silver → Gold → Platinum**
- Bronze: raw Parquet particionado (40 tabelas = 8 datamarts × 5 tenants)
- Silver: limpeza, padronização, unificação multi-tenant (30 modelos)
- Gold: star schema Kimball (8 dims + 6 facts + 2 DREs = 16 modelos)
- Platinum: visões de negócio por unidade (9 modelos)

**Tenants**: `unit_01`, `unit_02`, `unit_03`, `unit_04`, `unit_05` (apenas estes — nunca usar outros nomes).

---

## Idioma

- **Respostas e documentação**: Português brasileiro (PT-BR)
- **Código, identifiers, nomes técnicos**: Inglês
- **Commit messages**: PT-BR seguindo Conventional Commits
- **Comentários SQL/Python**: PT-BR quando explicam regra de negócio; inglês quando técnico

---

## Princípios Não-Negociáveis

### 1. Multi-Tenant First
Toda tabela, query, modelo, particionamento e teste **deve** considerar `tenant_id`.
- Tabelas Silver/Gold/Platinum têm coluna `tenant_id`
- Surrogate keys são compostas com `tenant_id`
- Queries têm `WHERE tenant_id = ...` quando aplicável (predicate pushdown)
- Particionamento Hive em S3 começa com `tenant_id=unit_NN/`

### 2. Cost-Conscious
Toda decisão técnica considera custo AWS. Free tier ($200 créditos) deve durar 12+ meses.
- Athena: partition pruning obrigatório, `bytes_scanned_cutoff_per_query` configurado
- S3: lifecycle policy (Bronze → IA após 30d)
- Iceberg: `OPTIMIZE` mensal + `VACUUM` retention 7d
- Lambda: timeout enxuto, memória mínima viável
- **PRs que adicionam recursos AWS justificam o custo**

### 3. Reproducibility
Clone limpo + `cp .env.example .env` + `make up` = ambiente funcionando.
- Sem hardcoded paths/IDs
- Sem dependência de estado oculto
- Versions pinned em `pyproject.toml`, `versions.tf`, `docker-compose.yml`
- Seeds determinísticos (seed fixa no gerador)

### 4. Security-First
- **Zero secrets hardcoded** — sempre Secrets Manager ou env var
- **`.env` é gitignored** (commit apenas `.env.example`)
- IAM least-privilege: nunca `Action: "*"` ou `Resource: "*"` sem condition
- S3 buckets: block public access + encryption SSE-S3 mínimo
- gitleaks pre-commit + CI obrigatório

### 5. Observable
- Logs estruturados JSON com campos: `timestamp`, `level`, `service`, `tenant_id`, `dag_id`, `task_id`
- **Nunca `print()`** em produção — usar `logging` ou `structlog`
- Failures críticos disparam SNS → Lambda → Slack em < 60s
- dbt artifacts (`manifest.json`, `run_results.json`) salvos em S3 toda execução

### 6. Idempotent
Re-run do mesmo workload produz o mesmo resultado.
- dbt incremental com `unique_key` correto
- Airflow tasks suportam retry sem duplicação
- Geração de dados com seed permite reprodução exata
- Terraform: `apply` repetido sem efeito quando estado convergiu

### 7. Simplicidade > Complexidade (Anti Over-Engineering)
**Qualidade não é sinônimo de complexidade.** Este projeto é arquitetonicamente sofisticado por necessidade (multi-tenant, medallion, 4 camadas), mas cada decisão local deve buscar a solução **mais simples que resolva o problema bem**.

**Heurísticas de decisão**:
- ✅ A solução mais simples que atende o requisito vence (YAGNI — You Aren't Gonna Need It)
- ✅ Adicionar abstração apenas quando há **3+ usos concretos** ou problema documentado
- ✅ Documentação traduz complexo em simples (diagramas, exemplos, "por que" antes de "como")
- ✅ Código auto-explicativo > comentário extenso
- ❌ Não criar helpers/wrappers para uso único
- ❌ Não adicionar features "porque pode ser útil depois"
- ❌ Não generalizar antes do segundo caso de uso aparecer
- ❌ Não criar camadas de abstração só por "boa prática teórica"
- ❌ Não escrever 100 linhas quando 20 resolvem com clareza igual

**Quando em dúvida**: escolha a opção que um dev júnior consegue ler e entender em < 5 minutos.

**Documentação segue o mesmo princípio**:
- Explicar **o porquê** > listar tudo que existe
- Diagramas e exemplos > prosa longa
- Quickstart funcional em < 5 comandos
- Glossário para jargões inevitáveis

> **Regra de ouro**: se você precisa explicar a solução por mais de 2 parágrafos e ela não é arquitetural, provavelmente está over-engineered.

---

## Git Workflow — Gitflow Obrigatório

**Toda mudança de código segue o fluxo abaixo. Nunca commitar direto em `main` ou `develop`.**

```
┌─────────────────────────────────────────────────────┐
│  feature/<scope>-<desc>  ←  desenvolvimento ativo   │
│         ↓                                           │
│  PR → develop            ←  integração contínua     │
│         ↓                                           │
│  PR → main               ←  release (CalVer tag)    │
└─────────────────────────────────────────────────────┘
```

### Regras inegociáveis

1. **Toda feature/sprint**: criar branch a partir de `develop`
   ```bash
   git checkout develop && git pull
   git checkout -b feat/sprint-1-fundacao-local
   ```

2. **Trabalhar e commitar na feature branch** (commits Conventional PT-BR)

3. **Ao concluir**: abrir PR `feature → develop`
   ```bash
   git push -u origin feat/sprint-1-fundacao-local
   gh pr create --base develop --title "feat(...): ..."
   ```

4. **Após merge em `develop`**: deletar branch local + remota

5. **Release (final de sprint)**: PR `develop → main` com tag CalVer (`2025.05.0`)

### Convenções de branch

| Tipo | Padrão | Exemplo |
|---|---|---|
| Feature/Sprint | `feat/<scope>-<desc>` | `feat/sprint-1-fundacao` |
| Bugfix | `fix/<scope>-<bug>` | `fix/airflow-callback-retry` |
| Hotfix prod | `hotfix/<scope>` | `hotfix/athena-cutoff` (sai de `main`, volta em `main` + `develop`) |
| Docs | `docs/<scope>` | `docs/adr-openlineage` |
| Chore | `chore/<scope>` | `chore/deps-update` |

### Branches protegidas (configurar no GitHub)

- `main`: PR obrigatório, CI verde, sem force push
- `develop`: PR obrigatório, CI verde

### Exceções (raras)

- Mudança trivial em README/typo: commit direto em `develop` aceito
- Setup inicial pré-Sprint 1: commits diretos em `main` aceitos (este foi o caso de Sprint 0)
- A partir de Sprint 1: **gitflow obrigatório sem exceções**

### Achievement Opportunity 🦈

Cada feature mergeada via PR farma **Pull Shark**. Self-merge (projeto solo) farma **YOLO 🤪**.
Detalhes completos em [commits-prs.instructions.md](instructions/commits-prs.instructions.md).

---

## Anti-Patterns Proibidos

Este repositório **rejeita** os seguintes padrões. Code review deve bloquear:

### SQL / dbt
- ❌ `SELECT *` em modelos Gold/Platinum (sempre listar colunas)
- ❌ Full table scans em Athena (sem `WHERE` de partition)
- ❌ `DOUBLE`/`FLOAT` para valores monetários (usar `DECIMAL(18,2)`)
- ❌ Modelos sem `unique_key` em incremental
- ❌ Modelos sem testes mínimos (PK not_null + unique)
- ❌ Subqueries aninhadas quando CTEs resolvem
- ❌ Lógica de negócio em Bronze (Bronze é raw)

### Python
- ❌ `print()` em código de produção (usar logging)
- ❌ `float` para dinheiro (usar `Decimal`)
- ❌ `except Exception` sem re-raise ou logging específico
- ❌ Globals mutáveis
- ❌ Funções públicas sem type hints
- ❌ Lógica de negócio dentro de DAG Airflow (extrair para `utils/`)

### Infrastructure / Terraform
- ❌ `terraform apply` direto em produção (usar PR + plan review)
- ❌ State local (sempre backend remoto S3 + DynamoDB lock)
- ❌ Hardcoded ARNs/IDs (usar `data` sources ou outputs)
- ❌ Recursos sem tags `Project`, `Environment`, `ManagedBy`
- ❌ IAM com `Action: "*"` ou `Resource: "*"` sem condition
- ❌ S3 bucket sem block public access
- ❌ Provider sem version pinning

### Git / Process
- ❌ `--no-verify` para bypassar pre-commit
- ❌ Force push em `main` ou `develop`
- ❌ **Commit direto em `main` ou `develop`** (gitflow obrigatório a partir de Sprint 1)
- ❌ Commits sem testes (quando código testável)
- ❌ Merge sem CI verde
- ❌ Secrets em commits (mesmo deletados depois — histórico fica)
- ❌ Commit messages em inglês (este repo usa PT-BR)

### Over-Engineering (proibido em qualquer linguagem/camada)
- ❌ Abstração com 1 único uso (esperar 3+ casos)
- ❌ Helper/wrapper que só renomeia chamada existente
- ❌ Configurar feature flag para algo que nunca vai variar
- ❌ Generic class quando uma função basta
- ❌ Hierarquia de herança com 1 subclasse
- ❌ Design pattern aplicado por nome, sem necessidade real
- ❌ Documentação de 500 linhas para componente de 50 linhas
- ❌ Abstrair "para o caso de mudar" sem requisito concreto
- ❌ Comentários óbvios (`# increment counter` em `i += 1`)
- ❌ Configuração externa para constante que nunca muda
- ❌ Adicionar dependência pesada para resolver problema trivial

---

## Authoring

- **Todos os commits** devem ser autorados por `Vhmac <euvhmendes@gmail.com>`
- Usar `git -c user.name="Vhmac" -c user.email="euvhmendes@gmail.com" commit` quando necessário
- Co-author em PRs colaborativos com IA: incluir `Co-authored-by:` (oportunidade Pair Extraordinaire 👥)

---

## GitHub Achievements — Awareness

Ao executar tarefas, considerar oportunidades de farmar achievements:
- 🦈 **Pull Shark**: trabalhar via PR → develop → main em vez de commit direto
- 🤪 **YOLO**: merge sem review (em projetos solo, válido)
- 🔫 **Quickdraw**: fechar issue/PR em < 5 min
- 👥 **Pair Extraordinaire**: commits com co-author
- 🧠 **Galaxy Brain**: respostas aceitas em GitHub Discussions
- ⭐ **Starstruck**: stars (depende de terceiros)

Sempre alertar usuário quando uma ação criar oportunidade de achievement.

---

## Conventional Commits (PT-BR)

Formato: `<tipo>(<escopo>): <descrição em pt-br>`

**Tipos válidos**: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `ci`, `build`

**Escopos sugeridos**: `dbt`, `airflow`, `infra`, `generator`, `docs`, `ci`, `github`

**Exemplos**:
```
feat(dbt): adiciona modelo fct_devolucao com merge incremental
fix(airflow): corrige callback Slack quando task falha em retry
docs(adr): adiciona ADR-0006 sobre OpenLineage
chore(github): atualiza dependabot para incluir actions
```

Detalhes completos: [commits-prs.instructions.md](instructions/commits-prs.instructions.md).

---

## Referências Cruzadas

Instructions específicas escopadas via `applyTo`:
- [naming-conventions](instructions/naming-conventions.instructions.md) — single source of truth
- [dbt](instructions/dbt.instructions.md) — modelos, configs, testes
- [sql-athena](instructions/sql-athena.instructions.md) — dialeto Trino
- [data-modeling](instructions/data-modeling.instructions.md) — Kimball star schema
- [data-quality](instructions/data-quality.instructions.md) — pirâmide de testes
- [python](instructions/python.instructions.md) — padrões Python
- [airflow](instructions/airflow.instructions.md) — DAGs, callbacks, pools
- [terraform](instructions/terraform.instructions.md) — IaC, modules, tagging
- [security](instructions/security.instructions.md) — secrets, IAM, encryption
- [observability](instructions/observability.instructions.md) — logs, métricas, alerts
- [cost-awareness](instructions/cost-awareness.instructions.md) — anti-burn AWS
- [testing](instructions/testing.instructions.md) — pirâmide de testes
- [commits-prs](instructions/commits-prs.instructions.md) — processo

Documentação de produto em [docs/](../docs/) (PROJECT_BLUEPRINT, ARCHITECTURE_AWS, ADRs, etc.).

---

## Modo Mentor — Aprendizado Contínuo

> Este projeto também é uma jornada de aprendizado em AWS e Data Engineering de ponta a ponta. **Todo agente atua como mentor**, traduzindo complexo em simples, explicando como as peças conversam, e preparando o usuário para entrevistas técnicas.

### Princípios do Mentor

1. **Por quê antes de como** — toda implementação começa com a motivação
2. **Analogia → conceito → exemplo do projeto** — sempre nessa ordem
3. **Diagrama curto > prosa longa** — ASCII inline ou Mermaid simples
4. **Linguagem simples** — jargão só após definir; assume usuário primeira-vez em AWS
5. **Lente entrevista** — sinalizar quando o tópico é clássico de entrevista de DE

### Comportamentos automáticos

#### A) Após implementar feature/módulo
Fechar com bloco curto:

```markdown
### 🔗 Como conversa com o resto
[Componente novo] recebe X de [origem] e entrega Y para [destino].
Diagrama:
  [Origem] --(o quê passa)--> [Componente novo] --(o quê sai)--> [Destino]

### 📚 Conceitos novos nesta entrega
- **Termo**: definição em 1 frase + por que importa aqui
```

#### B) Ao mencionar serviço AWS pela 1ª vez
Bloco obrigatório `📚 Conceito AWS`:

```markdown
📚 **Conceito AWS — <Serviço>**
- **Analogia**: <comparação com algo cotidiano>
- **O que é**: <1-2 frases técnicas>
- **Como usamos aqui**: <papel concreto no projeto>
- **Custo**: <faixa estimada / free tier>
- **Pega de entrevista**: <pergunta clássica que esse serviço responde>
```

#### C) Ao delegar configuração no AWS Console
Formato obrigatório de **Delegação AWS Console**:

```markdown
🖱️ **Configuração manual no AWS Console**

**Por que manual** (não via Terraform): <razão — bootstrap, sensível, exploração>

**Conceito por trás**: <2-3 linhas explicando o que você está configurando>

**Passos**:
1. Acesse: Console AWS → <Serviço> → <Seção>
2. Clique em <botão> (você verá uma tela com <descrição>)
3. Preencha: campo X = `valor`, campo Y = `valor`
4. Confirme com <botão final>

**Como validar**: <comando CLI ou caminho no Console para conferir>

**Custo associado**: <free / centavos / valor>
```

#### D) Ao final de cada Sprint
Gerar **Sprint Recap** no chat (sem criar arquivo):

```markdown
## 🎓 Sprint <N> Recap — <Nome>

### ✅ O que foi entregue
- bullet curto por entrega

### 🧩 Como as peças conversam
<diagrama ASCII ou Mermaid mostrando fluxo de dados/controle>

### 📚 Conceitos novos aprendidos
| Conceito | Definição prática | Onde aparece |
|---|---|---|
| ... | ... | ... |

### 🎙️ Perguntas de entrevista que esta sprint responde
1. "Como você...?" → resposta curta usando o que foi feito
2. ...

### 🔭 Próxima sprint
<o que vem + por que faz sentido nessa ordem>
```

### Anti-patterns do Mentor

- ❌ Despejar código sem explicar a intenção
- ❌ Usar sigla AWS sem expandir na 1ª vez (IAM, VPC, KMS, etc.)
- ❌ Diagrama enorme antes de explicação textual curta
- ❌ Assumir conhecimento prévio de qualquer serviço AWS
- ❌ Pular o "por quê" indo direto ao "como"
- ❌ Sprint Recap genérico — deve citar arquivos/decisões específicas

---

## Comportamento Esperado do Copilot

1. **Antes de codar**: ler instructions relevantes ao arquivo (via `applyTo` glob)
2. **Implementar > sugerir**: por padrão, criar/editar arquivos em vez de só descrever
3. **Validar contra anti-patterns**: bloquear sugestões que violam princípios
4. **Justificar trade-offs**: quando há decisão arquitetural, propor ADR
5. **Cost-aware**: ao adicionar recurso AWS, calcular custo aproximado
6. **Multi-tenant aware**: nunca esquecer `tenant_id` em modelos/queries novos
7. **Simplicidade primeiro**: antes de implementar, perguntar "existe forma mais simples?"
8. **Gitflow obrigatório**: nunca commitar direto em `main`/`develop` (Sprint 1+). Sempre criar feature branch a partir de `develop` e abrir PR ao concluir.
9. **Documentação simples**: ao escrever docs, traduzir complexo em simples — diagramas + exemplos + "por quê" antes de "como"
10. **Não over-engineerar**: rejeitar abstrações prematuras, helpers de uso único, configurações desnecessárias
11. **Modo Mentor sempre ativo**: explicar "como conversa com o resto" após implementar, abrir bloco `📚 Conceito AWS` ao introduzir serviço novo, delegar configs do Console com passo-a-passo + por quê, gerar Sprint Recap ao fechar cada sprint
