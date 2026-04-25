-- depends_on: {{ ref('silver_dw_lancamento_origem') }}
{{
    config(
        materialized='incremental',
        unique_key='sk_dre',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

with 
lancamentos as (
    select 
        data_lancamento, ano, mes, numero_lancamento, documento,
        id_empresa, id_unidade, id_conta, id_centro_custo,
        quantidade, tipo_lancamento, valor, empresa
    from {{ ref('silver_dw_lancamento_origem') }}
),
contas as (
    select id_conta, descricao_conta, estrutura_hierarquica, tipo_conta, natureza_conta, empresa
    from {{ ref('silver_dw_conta_contabil') }}
),
unidades as (
    select id_unidade, id_empresa, nome_unidade, sigla_unidade, empresa
    from {{ ref('silver_dw_unidade') }}
),
empresas as (
    select id_empresa, nome_empresa, nome_fantasia, empresa
    from {{ ref('silver_dw_empresa') }}
),
centros_custo as (
    select id_centro_custo, id_empresa_original as id_empresa, descricao_centro_custo, empresa
    from {{ ref('silver_dw_ccusto_contabil') }}
)

select
    concat(
        l.empresa, '_',
        cast(l.ano as string), '_',
        cast(l.mes as string), '_',
        cast(l.numero_lancamento as string), '_',
        cast(l.id_conta as string), '_',
        cast(l.id_centro_custo as string)
    ) as sk_dre,
    l.empresa,
    l.data_lancamento,
    l.ano,
    l.mes,
    l.numero_lancamento,
    l.documento,
    e.nome_empresa,
    e.nome_fantasia as nome_fantasia_empresa,
    u.nome_unidade,
    u.sigla_unidade,
    l.id_centro_custo,
    cc.descricao_centro_custo,
    l.id_conta,
    c.descricao_conta as nome_conta_contabil,
    c.estrutura_hierarquica as estrutura_conta,
    c.tipo_conta,
    c.natureza_conta,
    l.quantidade,
    l.tipo_lancamento,
    l.valor,
    case 
      when l.tipo_lancamento = 'Credito' then l.valor
      when l.tipo_lancamento = 'Debito' then l.valor * -1
      else 0
    end as valor_final
from 
    lancamentos l
left join contas c on l.id_conta = c.id_conta and l.empresa = c.empresa
left join unidades u on l.id_unidade = u.id_unidade and l.id_empresa = u.id_empresa and l.empresa = u.empresa
left join empresas e on l.id_empresa = e.id_empresa and l.empresa = e.empresa
left join centros_custo cc on l.id_centro_custo = cc.id_centro_custo and l.empresa = cc.empresa

{% if is_incremental() %}
where l.data_lancamento > (SELECT COALESCE(MAX(data_lancamento), '2000-01-01') FROM {{ this }})
{% endif %}
