-- depends_on: {{ ref('silver_dw_saldo_contabil') }}
{{
    config(materialized='table')
}}

with 
saldos_silver as (
    select
        id_empresa,
        id_filial,
        id_unidade,
        id_conta,
        id_conta_superior,
        ano,
        mes,
        data_saldo,
        valor_debito_mes,
        valor_credito_mes,
        empresa
    from 
        {{ ref('silver_dw_saldo_contabil') }}
),
contas_silver as (
    select
        id_conta,
        descricao_conta,
        grau,
        tipo_conta,
        estrutura_hierarquica,
        natureza_conta,
        empresa
    from 
        {{ ref('silver_dw_conta_contabil') }}
)
select
    cs.descricao_conta,
    ss.id_conta,
    cs.grau,
    cs.tipo_conta,
    cs.estrutura_hierarquica,
    cs.natureza_conta,
    ss.id_conta_superior,
    ss.id_empresa,
    ss.id_unidade,
    ss.id_filial,
    ss.ano,
    ss.mes,
    ss.data_saldo,
    ss.empresa,
    sum(ss.valor_debito_mes) as total_debito,
    sum(ss.valor_credito_mes) as total_credito,
    round(sum(ss.valor_credito_mes) - sum(ss.valor_debito_mes), 2) as realizado_consolidado
from
    saldos_silver as ss
inner join
    contas_silver as cs on ss.id_conta = cs.id_conta and ss.empresa = cs.empresa
group by
    cs.descricao_conta, ss.id_conta, cs.grau, cs.tipo_conta, cs.estrutura_hierarquica,
    cs.natureza_conta, ss.id_conta_superior, ss.id_empresa, ss.id_unidade,
    ss.id_filial, ss.ano, ss.mes, ss.data_saldo, ss.empresa
order by
    ss.ano, ss.mes, cs.estrutura_hierarquica, ss.empresa
