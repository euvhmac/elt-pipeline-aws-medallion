# Narrativa de Entrevista

Três versões do pitch do projeto, conforme tempo disponível: **5 min**, **15 min**, **30 min**. Use para entrevistas técnicas, conversas de portfólio, ou apresentações.

---

## Pitch 5 minutos — Visão executiva

**Audiência**: recrutador técnico, screening inicial.

### Estrutura (1 min cada)

**1. Contexto** *(1 min)*

> "Trabalhei em um projeto interno corporativo onde projetamos uma plataforma analítica multi-tenant em Azure Databricks com Delta Lake e Airflow no AKS. Ao sair, quis recriar essa arquitetura como portfólio público, mas em AWS — para demonstrar capacidade de modernizar e migrar plataformas analíticas entre clouds. O objetivo era replicar 100% da lógica de negócio (8 datamarts, 5 unidades, ~55 modelos dbt) com infra significativamente mais barata."

**2. Decisão Arquitetural Principal** *(1 min)*

> "A decisão central foi substituir o Databricks SQL Warehouse por Athena com Apache Iceberg. O ganho: pay-per-query em vez de cluster sempre ligado, e Iceberg dá ACID + time travel + schema evolution sobre S3 puro. Reduzi custo mensal de ~$800 para ~$6, mantendo lineage completo no dbt e suporte a `MERGE` para incrementais."

**3. Stack** *(1 min)*

> "S3 + Iceberg para storage; Athena engine v3 (Trino) para queries; AWS Glue como catálogo; dbt-athena para transformação; Airflow rodando em Docker Compose local — orquestrando jobs que executam queries Athena. Terraform para infra, GitHub Actions para CI, SNS+Lambda para alertas. Todos os modelos dbt rodam diariamente via DAG event-driven (Datasets), com 5 tenants particionados por Hive."

**4. Resultados** *(1 min)*

> "55 modelos dbt em Bronze→Silver→Gold→Platinum, 80%+ cobertura de testes, CI bloqueando PRs com SQL inválido ou secrets expostos, infra inteira em Terraform com `terraform apply` em < 3 min, custo mensal validado em $5-7. Repositório público com documentação completa: arquitetura, ADRs, runbook, sprint roadmap."

**5. Por que importa** *(1 min)*

> "Esse projeto demonstra três coisas: (1) capacidade de tomar decisões arquiteturais defensáveis com trade-offs explícitos via ADRs, (2) entendimento end-to-end de um pipeline de produção real (não tutorial), e (3) disciplina de engenharia: CI/CD, testes, observabilidade, custo controlado. É exatamente o que um Tech Lead de Data Engineering precisa entregar."

---

## Pitch 15 minutos — Deep dive técnico

**Audiência**: entrevista técnica com Tech Lead ou Staff Engineer.

### Roteiro

**Minutos 0-2: Contexto + Problema** *(reuse do 5min)*

**Minutos 2-5: Arquitetura Macro** *(diagrama)*

Mostrar [ARCHITECTURE_AWS.md](ARCHITECTURE_AWS.md) — diagrama 1.

> "A arquitetura segue padrão Medallion clássico, mas com uma característica: orquestração event-driven via Airflow Datasets. Cada datamart de Bronze é um Dataset; quando todos os 8 são atualizados pela DAG `dag_synthetic_source`, a DAG de transformação `dag_dbt_aws_detailed` dispara automaticamente. Isso elimina cron schedules duplicados e garante que dbt só roda quando há dados novos — economiza Athena query time."

**Minutos 5-10: Decisão Crítica — Iceberg vs Delta**

Abrir [adr/0001-iceberg-vs-delta.md](adr/0001-iceberg-vs-delta.md).

> "A decisão mais controversa foi escolher Iceberg em vez de Delta Lake. Delta tem mais maturidade e era o que usava no Azure. Mas para AWS:
> 
> 1. **Athena suporte nativo**: Iceberg é first-class no engine v3. Delta requer Athena Iceberg compatibility layer (não recomendado)
> 2. **Open governance**: Iceberg vai para Apache Foundation, Delta ainda é Linux Foundation com governança Databricks-influenced
> 3. **Multi-engine**: Iceberg lê em Spark, Trino, Flink, Snowflake. Delta foi multi-engine só recentemente
> 4. **`MERGE` syntax**: Iceberg tem MERGE padrão SQL; dbt-athena suporta nativamente com `incremental_strategy='merge'`
> 
> Trade-off: ferramentas downstream (DBT_LABS, Datafold) ainda têm cobertura melhor para Delta."

**Minutos 10-13: Demo de uma camada — Silver**

Abrir [MEDALLION_LAYERS.md](MEDALLION_LAYERS.md) → seção Silver.

Mostrar exemplo de modelo Silver com:
- `incremental` + `merge`
- Lookback window de 1 dia
- `unique_key` composto `[tenant_id, venda_id]`
- Audit column `_dbt_loaded_at`

> "Cada Silver é incremental com merge. O lookback de 1 dia captura late-arriving facts; o composite unique key resolve ambiguidade entre tenants; e o `on_schema_change='append_new_columns'` permite que produtor adicione campos novos sem quebrar pipeline. Em produção real, isso é crucial — sources mudam schema sem aviso."

**Minutos 13-15: CI/CD + Custos**

Abrir [CI_CD.md](CI_CD.md):

> "O CI tem 3 workflows. O mais interessante é o `dbt-ci`: usa `state:modified+ --defer`, ou seja, só roda modelos alterados E seus descendentes, lendo upstream do schema de produção. Um PR que altera 1 modelo Silver roda 5 modelos em vez de 55. Tempo médio de CI: < 5 min."

Mencionar [COST_ESTIMATE.md](COST_ESTIMATE.md):

> "Custo total ~$6/mês validado. 99% de redução vs solução Azure original — viabilizando portfólio permanente."

---

## Pitch 30 minutos — End-to-end + troubleshooting

**Audiência**: entrevista técnica final, painel de Staff/Principal Engineers.

### Roteiro

**Minutos 0-3: Contexto Estendido**

Adicionar à versão 5min:

> "Decidi explicitamente NOT migrar 1:1. Mantive a estrutura de modelos (~55) e lógica de negócio, mas adaptei para padrões AWS: Iceberg em vez de Delta, dbt-athena em vez de dbt-databricks, gerador Python em vez de Airbyte, Airflow Docker em vez de Helm. Cada decisão tem ADR documentando trade-offs."

**Minutos 3-8: Arquitetura — Todos os 4 Diagramas**

Walkthrough [ARCHITECTURE_AWS.md](ARCHITECTURE_AWS.md):
1. Diagrama macro (storage + compute)
2. Fluxo de dados Medallion
3. Orquestração event-driven
4. Observabilidade
5. CI/CD

Em cada um, destacar **decisão**:
- Por que 4 buckets separados (não 1 com prefixos)? Lifecycle policies + permissions granulares
- Por que Datasets em vez de TriggerDagOperator? Decoupling, melhor visibilidade no UI
- Por que SNS+Lambda em vez de Slack callback direto no Airflow? Reusabilidade — outros sistemas podem publicar no SNS, e isolar credenciais Slack

**Minutos 8-13: Migração Detalhada**

Abrir [MIGRATION_FROM_AZURE.md](MIGRATION_FROM_AZURE.md):

> "Maior surpresa foi a quantidade de funções Spark SQL que NÃO têm equivalente direto em Trino. Exemplo: `to_date(col, 'yyyy-MM-dd')` em Spark; em Trino é `date_parse(col, '%Y-%m-%d')` retornando timestamp, depois `CAST AS DATE`. Tive que mapear ~40 funções. Documento `MIGRATION_FROM_AZURE.md` lista todas."

Mostrar tabela de mapping de funções.

**Minutos 13-18: Demo Profundo de uma Camada Gold**

Pegar `fct_vendas`. Walkthrough de:
- Surrogate key generation (composite com tenant_id)
- Joins com 5 dimensions
- Estratégia incremental
- Testes (unique, not_null, relationships)

```sql
{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['tenant_id', 'venda_id'],
    on_schema_change='append_new_columns',
    table_type='iceberg'
) }}
```

> "Tudo aqui é intencional. `unique_key` composite porque a mesma `venda_id` pode existir em tenants diferentes. `merge` em vez de `delete+insert` porque mantém atomicidade. `iceberg` porque Athena precisa para suportar merge. `on_schema_change='append_new_columns'` porque o produtor adiciona campos."

**Minutos 18-23: Troubleshooting Story**

> "Maior bug que encontrei foi com partition projection. Configurei o Glue table com projection.tenant_id como type=enum, mas em uma versão antiga eu tinha `type=injected`. Athena começou a retornar 0 registros, mesmo com dados em S3. Demorou 2 horas para descobrir.
> 
> Diagnóstico:
> 1. Confirmei que arquivos existem em S3 com `aws s3 ls`
> 2. Tentei MSCK REPAIR — não funcionou (porque com projection, não tem partition no metastore)
> 3. Verifiquei `SHOW TBLPROPERTIES` no Athena — vi a config errada
> 4. Corrigi com `ALTER TABLE SET TBLPROPERTIES`
> 5. Adicionei testes Terraform para detectar drift
> 
> Lição: partition projection é poderoso mas frágil. Hoje tenho um `validate_partitions.py` que roda no CI."

**Minutos 23-26: Observabilidade**

> "Falhas de pipeline disparam SNS → Lambda → Slack em < 60s. Lambda parsa o evento Airflow, formata Block Kit message com link para UI. CloudWatch Dashboard agrega métricas de Athena (queries/dia, scan size, falhas) e custo. Manifest do dbt salvo em S3 a cada run permite future lineage tools (Datafold-like).
> 
> Próximo passo: integrar OpenLineage para emitir eventos para Marquez ou Datakin."

**Minutos 26-30: Reflexão + Próximos Passos**

> "O que faria diferente:
> 
> 1. **Streaming**: hoje é batch diário. Próxima iteração seria CDC via Kinesis ou MSK + Iceberg streaming writes. Iceberg suporta nativamente.
> 
> 2. **Testes mais sofisticados**: usar dbt-expectations e Great Expectations para validações de distribuição/range em facts. Hoje tenho schema tests apenas.
> 
> 3. **Multi-region DR**: hoje é single-region. Em produção real, replicar S3 para region secundária + DR runbook.
> 
> 4. **Custo dinâmico**: o que mais surpreendeu foi quão pouco Athena custa para volumes pequenos. Mas para 100x o volume, EMR Serverless começa a fazer sentido. ADR-0002 cobre essa fronteira.
> 
> No portfólio, esse projeto provou que entendo end-to-end de uma plataforma analítica moderna: storage, compute, orquestração, qualidade, observabilidade, custo, e CI/CD. E que eu tomo decisões com trade-offs explícitos — não escolho ferramenta porque é hype."

---

## Perguntas Difíceis Antecipadas

### "Por que não Snowflake / BigQuery?"

> "Trade-off de custo vs flexibilidade. Snowflake/BQ teriam DX melhor, mas: (a) custo fixo mais alto inviabiliza demo permanente; (b) lock-in de vendor; (c) este projeto é para demonstrar AWS + open formats — Iceberg é estratégico para evitar lock-in. Se o requisito fosse 'plataforma corporativa para analista de negócio', Snowflake seria recomendado."

### "Por que Airflow local em vez de MWAA?"

ADR-0003. > "MWAA custa ~$350/mês mínimo (small). Para um projeto demonstrativo isso quebra o argumento de custo. Local Docker prova que o autor entende Airflow + DAGs sem depender de gerência cloud. Para produção real, MWAA ou Astronomer Cloud seria recomendado."

### "Como você lidaria com 100x mais volume?"

> "Três mudanças:
> 1. **Compute**: migrar Athena → EMR Serverless ou Trino self-hosted. Athena tem cap de 30 min/query e fica caro acima de ~10 TB/mês.
> 2. **Ingestão**: substituir gerador Python por Kinesis Firehose + Lambda compactação.
> 3. **dbt**: dividir DAG monolítica em DAGs por domínio + dbt mesh (multi-project)."

### "Como você garante que migração preserva lógica de negócio?"

> "(a) Modelos Silver têm testes de schema rigorosos; (b) Comparações Athena vs Databricks SQL: rodei ambos em paralelo durante migração com sample idêntico, comparei agregações chave (sum vendas por mês/tenant) — qualquer diferença > 0.1% é investigada; (c) DREs têm singular tests validando que débitos = créditos."

### "Você usou IA para acelerar? Como?"

> "Sim. Usei Copilot/Claude para: (a) traduzir funções Spark→Trino em batch; (b) gerar boilerplate Terraform; (c) revisar SQL para edge cases. Mas decisões arquiteturais, ADRs, e debugging de partition projection foram meus. IA é amplificador — não substitui entendimento de fundamentos."

---

## Storytelling — Estrutura STAR

Para cada bullet de currículo, use STAR (Situation, Task, Action, Result):

**Exemplo**:
- **S**: Plataforma analítica corporativa em Azure com custo ~$800/mês ficou inacessível para portfólio público
- **T**: Migrar arquitetura para AWS mantendo lógica de negócio (~55 modelos) com custo viável (<$10/mês)
- **A**: Substitui Delta→Iceberg, DBSQL→Athena, AKS→Docker local, Airbyte→gerador Python; documentou 5 ADRs; implementou CI/CD com bloqueio de quality gates
- **R**: 99% redução de custo ($800→$6/mês); 100% paridade funcional; pipeline rodando em < 30 min end-to-end; CI < 5 min

---

## Slides Sugeridos (caso apresentação formal)

1. **Capa**: título + autor + data
2. **Problema**: solução original e por que recriar
3. **Decisão**: AWS + Iceberg + Athena (1 frase + diagrama macro)
4. **Arquitetura**: diagrama Medallion + componentes
5. **Decisões controversas**: 3 ADRs principais
6. **Demo**: screenshot Airflow UI + dbt docs lineage
7. **Custo**: tabela comparativa Azure vs AWS
8. **CI/CD**: workflow diagram
9. **Lições**: 3 takeaways
10. **Próximos passos**: streaming, OpenLineage, multi-region

---

## Material de Apoio

- README do repo público: visão de portfólio
- Loom/screencast 90s: pipeline rodando end-to-end
- GitHub Pages: dbt docs com lineage interativo
- LinkedIn post: anunciar projeto com link + 1 insight técnico
