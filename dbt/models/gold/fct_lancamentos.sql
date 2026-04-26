-- fct_lancamentos: fato de lancamentos contabeis.
-- Grao: 1 linha por (tenant_id, lancamento_id).
-- Campo vlr_final: CREDITO = positivo, DEBITO = negativo (convencao contabil).
-- OBRIGATORIO antes do PR 8 (dre_contabil usa esta fato).

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'lancamento_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with lancamentos as (

    select
        tenant_id,
        lancamento_id,
        plano_conta_id,
        cd_tipo_lancamento,
        dt_competencia,
        vlr_lancamento,
        ds_historico,
        created_at
    from {{ ref('silver_dw_lancamentos') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

plano as (

    select
        tenant_id,
        plano_conta_id,
        plano_conta_sk,
        cd_tipo_conta
    from {{ ref('dim_plano_contas') }}

),

joined as (

    select
        {{ dbt_utils.generate_surrogate_key(['l.tenant_id', 'l.lancamento_id']) }} as lancamento_sk,
        l.tenant_id,
        l.lancamento_id,
        p.plano_conta_sk,
        p.cd_tipo_conta,
        l.cd_tipo_lancamento,
        cast(date_format(l.dt_competencia, '%Y%m%d') as integer)    as data_id,
        l.vlr_lancamento,
        -- convencao: credito positivo, debito negativo
        case
            when l.cd_tipo_lancamento = 'CREDITO'
                then l.vlr_lancamento
            else -l.vlr_lancamento
        end                                                          as vlr_final,
        l.ds_historico,
        l.dt_competencia,
        l.created_at
    from lancamentos l
    inner join plano p
        on l.tenant_id      = p.tenant_id
        and l.plano_conta_id = p.plano_conta_id

)

select
    lancamento_sk,
    tenant_id,
    lancamento_id,
    plano_conta_sk,
    cd_tipo_conta,
    cd_tipo_lancamento,
    data_id,
    vlr_lancamento,
    vlr_final,
    ds_historico,
    dt_competencia,
    created_at
from joined
