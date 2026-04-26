-- fct_expedicao: fato transacional de expedicao.
-- Grao: 1 linha por (tenant_id, expedicao_id).
-- venda_id e degenerate dimension (sem SK proprio — referencia direta).
-- transportadora_sk -> dim_transportadoras.
-- data_id -> dim_calendrio (baseado em dt_expedicao).

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'expedicao_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with expedicao as (

    select
        tenant_id,
        expedicao_id,
        venda_id,
        transportadora_id,
        dt_expedicao,
        dt_entrega_prevista,
        dt_entrega_realizada,
        ds_status,
        updated_at,
        created_at
    from {{ ref('silver_dw_expedicao') }}

    {% if is_incremental() %}
    where updated_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

transportadoras as (

    select
        tenant_id,
        transportadora_id,
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'transportadora_id']) }} as transportadora_sk
    from {{ ref('silver_dw_transportadoras') }}

),

joined as (

    select
        {{ dbt_utils.generate_surrogate_key(['e.tenant_id', 'e.expedicao_id']) }}  as expedicao_sk,
        e.tenant_id,
        e.expedicao_id,
        e.venda_id,                                        -- degenerate dim
        t.transportadora_sk,
        cast(date_format(e.dt_expedicao, '%Y%m%d') as integer)  as data_id,
        e.dt_expedicao,
        e.dt_entrega_prevista,
        e.dt_entrega_realizada,
        -- atraso em dias: negativo = antecipada, positivo = atrasada, null = nao entregue
        case
            when e.dt_entrega_realizada is not null
            then date_diff('day', e.dt_entrega_prevista, e.dt_entrega_realizada)
            else null
        end as nr_dias_atraso,
        e.ds_status,
        e.updated_at,
        e.created_at
    from expedicao e
    inner join transportadoras t
        on e.tenant_id = t.tenant_id
        and e.transportadora_id = t.transportadora_id

)

select
    expedicao_sk,
    tenant_id,
    expedicao_id,
    venda_id,
    transportadora_sk,
    data_id,
    dt_expedicao,
    dt_entrega_prevista,
    dt_entrega_realizada,
    nr_dias_atraso,
    ds_status,
    updated_at,
    created_at
from joined
