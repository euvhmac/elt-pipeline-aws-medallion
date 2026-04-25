# ADR-0001 — Apache Iceberg vs Delta Lake

- **Status**: Accepted
- **Data**: 2025-04-25
- **Decisores**: Vhmac (autor)
- **Tipo**: Architectural Decision Record (Michael Nygard format)

---

## Contexto

A plataforma analítica original utilizava **Delta Lake** sobre ADLS Gen2 + Databricks. Ao migrar para AWS, precisava de um **table format ACID** sobre S3. Os candidatos eram:

1. **Apache Iceberg** — Apache Software Foundation
2. **Delta Lake** — Linux Foundation (governança Databricks-influenced)
3. **Apache Hudi** — Apache (foco em CDC/streaming)

Critérios de avaliação:
- Suporte nativo no engine SQL escolhido (Athena)
- Maturidade e adoção pela indústria
- Compatibilidade com dbt-athena
- Open governance (evitar lock-in)
- Funcionalidades: time travel, schema evolution, MERGE
- Custo operacional (compactação, manutenção)

---

## Decisão

**Adotar Apache Iceberg** como table format único para todas as camadas Silver, Gold, Platinum.

---

## Justificativa

### Vantagens do Iceberg para este projeto

1. **Suporte nativo no Athena engine v3 (Trino)**:
   - `CREATE TABLE ... USING iceberg` é first-class
   - `MERGE INTO` funciona out-of-the-box
   - Sem necessidade de compatibility layer

2. **dbt-athena suporte**:
   - `table_type='iceberg'` + `incremental_strategy='merge'` funcionam direto
   - Comunidade ativa em `dbt-athena-community`

3. **Hidden partitioning**:
   - Não precisa filtrar manualmente por colunas de partição
   - Iceberg gerencia transparente

4. **Schema evolution**:
   - `on_schema_change='append_new_columns'` no dbt funciona
   - Não há rewrite de dados antigos

5. **Open governance**:
   - Apache top-level project desde 2020
   - Múltiplos vendors contribuem (Netflix, Apple, Tabular, AWS)
   - Sem dependência de Databricks

6. **Multi-engine**:
   - Athena, Trino, Spark, Flink, Snowflake, BigQuery (preview)
   - Mesmo dado, múltiplos consumidores

### Desvantagens aceitas

1. **Maturidade do ecossistema dbt**:
   - dbt-databricks tem mais features que dbt-athena
   - Algumas otimizações específicas do Delta não estão disponíveis

2. **Curva de aprendizado**:
   - Conceitos de manifest, snapshot, partition spec
   - Diferentes da abstração simplificada do Delta

3. **Compactação manual**:
   - `OPTIMIZE table REWRITE DATA` precisa ser agendado
   - Delta tem auto-compaction nativo no Databricks

---

## Comparação Detalhada

| Critério | Iceberg | Delta Lake | Hudi |
|---|---|---|---|
| Athena suporte | ✅ Nativo (engine v3) | ⚠️ Compatibility layer | ❌ Limitado |
| dbt-athena | ✅ Bem suportado | ❌ Não suportado nativamente | ❌ Não suportado |
| MERGE | ✅ SQL standard | ✅ SQL standard | ✅ SQL standard |
| Time travel | ✅ Snapshots | ✅ Versioning | ✅ Commits |
| Schema evolution | ✅ Append/rename/reorder | ✅ Append/rename | ✅ Append |
| Hidden partitioning | ✅ Sim | ❌ Não | ⚠️ Parcial |
| Multi-engine | ✅ Excelente | ⚠️ Melhorando | ⚠️ Spark-centric |
| Compactação auto | ❌ Manual (OPTIMIZE) | ✅ Auto-compact | ✅ Auto |
| Maturidade | Alta | Muito alta | Alta |
| Governança aberta | ✅ Apache | ⚠️ Linux Foundation | ✅ Apache |

---

## Consequências

### Positivas

- ✅ Migração SQL Spark→Trino simplificada (MERGE syntax compatível)
- ✅ Custo de armazenamento idêntico ao Parquet puro
- ✅ Time travel disponível para debugging (`FOR TIMESTAMP AS OF`)
- ✅ Schema evolution sem dor
- ✅ Repositório livre de lock-in cloud

### Negativas

- ⚠️ Necessário agendar `OPTIMIZE` mensal para evitar fragmentação
- ⚠️ Necessário agendar `VACUUM` para limpar snapshots antigos (custo S3)
- ⚠️ Algumas features do Delta (Liquid Clustering, Deletion Vectors) não disponíveis
- ⚠️ Comunidade dbt-athena menor que dbt-databricks

### Mitigações

- Compactação Iceberg agendada via DAG Airflow mensal (Sprint 6)
- VACUUM com retention 7 dias agendado mensalmente
- Documentar troubleshooting comum em [RUNBOOK.md](../RUNBOOK.md)

---

## Alternativas Consideradas

### Alternativa 1: Manter Delta + Athena Iceberg compat layer
- ❌ Performance ruim, várias features não funcionam
- ❌ Não recomendado pela AWS

### Alternativa 2: EMR + Delta nativo
- ❌ EMR cluster custa ~$100+/mês mínimo (vs Athena $0 idle)
- ❌ Adiciona complexidade operacional

### Alternativa 3: Hudi
- ❌ dbt-athena não suporta nativamente
- ❌ Comunidade menor para o caso de uso analítico

### Alternativa 4: Parquet puro (sem table format)
- ❌ Sem ACID, sem MERGE, sem schema evolution
- ❌ Não suporta padrões dbt incrementais avançados

---

## Referências

- [Apache Iceberg Specification](https://iceberg.apache.org/spec/)
- [AWS — Using Iceberg in Athena](https://docs.aws.amazon.com/athena/latest/ug/querying-iceberg.html)
- [dbt-athena Iceberg Support](https://github.com/dbt-athena/dbt-athena#iceberg)
- Comparação: [Onehouse - Lakehouse Storage Systems Comparison](https://www.onehouse.ai/blog/apache-hudi-vs-delta-lake-vs-apache-iceberg-lakehouse-feature-comparison)

---

## Revisão

A decisão será revisada se:
- AWS oficialmente recomendar Delta sobre Iceberg
- Athena adicionar suporte first-class para Delta
- Performance Iceberg em escala apresentar regressões
- Ecossistema dbt-athena estagnar
