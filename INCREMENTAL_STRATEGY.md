# 📊 Estratégia de Materialização Incremental - BigData DBT

## 🎯 Objetivo

Este documento descreve a implementação de **materialização incremental** para otimizar o processamento de dados no projeto DBT, reduzindo tempo de execução e consumo de recursos.

---

## 🔄 O que é Materialização Incremental?

A materialização incremental permite que o DBT processe **apenas os dados novos ou atualizados** desde a última execução, ao invés de reprocessar toda a tabela a cada vez.

### Benefícios:
- ⚡ **Performance**: Redução de até 90% no tempo de execução
- 💰 **Custo**: Menor consumo de recursos computacionais
- 🔄 **Eficiência**: Processamento apenas de dados alterados
- 📊 **Escalabilidade**: Suporta crescimento contínuo de dados

---

## 🏗️ Arquitetura Implementada

### Camada Silver (Staging)

| Modelo | Unique Key | Estratégia de Filtro | Campo de Controle |
|--------|-----------|---------------------|-------------------|
| `silver_dw_vendas` | `sk_venda_item` | Merge | `data_criacao` |
| `silver_dw_titulo_fin` | `sk_titulo_financeiro` | Merge | `data_movimento` |
| `silver_dw_saldos_contabeis` | `sk_saldo_contabil` | Merge | `data_criacao` |
| `silver_dw_lancamento_origem` | `['empresa', 'id_empresa', 'lancamento_numero', 'id_conta']` | Merge | `data_lancamento`, `timestamp_entrada_sistema` |

### Camada Gold (Fatos)

| Modelo | Unique Key | Estratégia de Filtro | Campo de Controle |
|--------|-----------|---------------------|-------------------|
| `fct_vendas` | `sk_venda_item` | Merge | `data_emissao_pedido` (7 dias) |
| `fct_titulo_financeiro` | `sk_titulo_financeiro` | Merge | `data_emissao`, `data_pagamento` (30 dias) |
| `dre_contabil` | `['empresa', 'lancamento_numero', 'id_conta']` | Merge | `data_lancamento` |

---

## ⚙️ Configuração dos Modelos

### Exemplo de Configuração

```sql
{{ config(
    materialized='incremental',
    unique_key='sk_venda_item',
    incremental_strategy='merge',
    schema='silver__multi_tenant_dw',
    on_schema_change='sync_all_columns'
) }}
```

### Parâmetros Explicados:

- **`materialized='incremental'`**: Define o modo incremental
- **`unique_key`**: Campo(s) que identificam registros únicos
- **`incremental_strategy='merge'`**: Usa MERGE (upsert) para atualizar ou inserir
- **`on_schema_change='sync_all_columns'`**: Sincroniza automaticamente mudanças de schema

### Lógica de Filtro Incremental

```sql
{% if is_incremental() %}
    -- Filtra apenas registros novos ou atualizados
    AND data_criacao > (SELECT MAX(data_criacao) FROM {{ this }})
{% endif %}
```

---

## 🚀 Como Executar

### 1. Primeira Execução (Full Refresh)

Na primeira execução ou quando precisar reprocessar tudo:

```bash
# Executar todos os modelos (cria as tabelas pela primeira vez)
dbt run

# Ou executar modelos específicos
dbt run --select silver_dw_vendas
dbt run --select fct_vendas
```

### 2. Execução Incremental (Padrão)

Em execuções subsequentes, apenas dados novos serão processados:

```bash
# Execução incremental padrão
dbt run

# Execução incremental de modelos específicos
dbt run --select silver_dw_vendas fct_vendas
```

### 3. Forçar Full Refresh

Quando necessário reprocessar todos os dados:

```bash
# Full refresh de todos os modelos
dbt run --full-refresh

# Full refresh de modelos específicos
dbt run --select silver_dw_vendas --full-refresh
```

### 4. Execução por Camada

```bash
# Executar apenas camada Silver
dbt run --select models/silver/*

# Executar apenas camada Gold
dbt run --select models/gold/*

# Executar camada específica com full refresh
dbt run --select models/silver/* --full-refresh
```

---

## 📅 Janelas de Processamento

Para garantir que atualizações tardias sejam capturadas, implementamos **janelas de sobreposição**:

### Silver Layer
- **Vendas**: Processa registros com `data_criacao > MAX(data_criacao)`
- **Títulos**: Processa registros com `data_movimento > MAX(data_movimento)`
- **Saldos**: Processa registros com `data_criacao > MAX(data_criacao)`
- **Lançamentos**: Processa registros com `data_lancamento > MAX(data_lancamento)`

### Gold Layer
- **Vendas**: Janela de 7 dias para capturar atualizações
- **Títulos**: Janela de 30 dias (títulos podem ser pagos posteriormente)
- **DRE**: Processa apenas lançamentos novos

---

## 🔍 Monitoramento e Validação

### Verificar se o Incremental está Funcionando

```sql
-- Verificar data máxima na tabela
SELECT MAX(data_emissao_pedido) FROM gold__multi_tenant_dw.fct_vendas;

-- Contar registros processados
SELECT COUNT(*) FROM gold__multi_tenant_dw.fct_vendas;
```

### Logs do DBT

```bash
# Ver logs detalhados da execução
dbt run --select silver_dw_vendas --debug

# Ver apenas warnings e erros
dbt run --select fct_vendas --warn-error
```

---

## 🛠️ Troubleshooting

### Problema: Dados não estão sendo atualizados

**Solução 1**: Verificar se há dados novos na fonte
```sql
SELECT MAX(data_criacao) FROM bronze__unit_01.dw_vendas;
```

**Solução 2**: Forçar full refresh
```bash
dbt run --select silver_dw_vendas --full-refresh
```

### Problema: Erro de chave duplicada

**Causa**: A `unique_key` não está identificando registros únicos corretamente

**Solução**: Revisar a definição da `unique_key` no modelo

### Problema: Performance ainda está lenta

**Verificações**:
1. Confirmar que o modo incremental está ativo (verificar logs)
2. Revisar filtros de data - podem estar muito amplos
3. Considerar particionamento das tabelas no warehouse

---

## 📋 Checklist de Implementação

- [x] ✅ Configurar `materialized='incremental'` nos modelos Silver
- [x] ✅ Configurar `materialized='incremental'` nos modelos Gold
- [x] ✅ Definir `unique_key` apropriada para cada modelo
- [x] ✅ Implementar filtros de data com `is_incremental()`
- [x] ✅ Adicionar janelas de sobreposição para garantir consistência
- [x] ✅ Documentar estratégia e campos de controle
- [ ] 🔄 Testar primeira execução (full refresh)
- [ ] 🔄 Testar execução incremental
- [ ] 🔄 Validar dados processados
- [ ] 🔄 Monitorar performance em produção

---

## 🎓 Boas Práticas

### 1. **Use Campos de Timestamp Confiáveis**
Sempre use campos de data/timestamp que reflitam quando o registro foi criado ou modificado.

### 2. **Janelas de Sobreposição**
Para dados que podem ser atualizados após a criação (ex: títulos financeiros), use janelas de dias para reprocessar registros recentes.

### 3. **Teste Regularmente**
Execute `--full-refresh` periodicamente em ambientes de desenvolvimento para validar a lógica completa.

### 4. **Monitore o Tamanho das Tabelas**
Use `ANALYZE TABLE` no warehouse para manter estatísticas atualizadas e otimizar queries.

### 5. **Documentação de Dependências**
Mantenha os comentários `depends_on` atualizados para facilitar a compreensão de dependências entre modelos.

---

## 🔗 Referências

- [DBT Incremental Models](https://docs.getdbt.com/docs/build/incremental-models)
- [DBT Incremental Strategies](https://docs.getdbt.com/docs/build/incremental-strategy)
- [Databricks Merge Strategy](https://docs.databricks.com/sql/language-manual/delta-merge-into.html)

---

## 📞 Suporte

Para dúvidas ou problemas:
1. Verificar este documento
2. Consultar logs do DBT: `dbt run --debug`
3. Contactar time de engenharia de dados

---

**Última Atualização**: 24 de Novembro de 2025  
**Versão**: 1.0  
**Autor**: Time de Engenharia de Dados
