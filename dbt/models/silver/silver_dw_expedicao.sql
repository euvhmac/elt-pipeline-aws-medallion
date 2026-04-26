-- silver_dw_expedicao: limpeza + padronizacao dos registros de expedicao.
-- Grao: 1 linha por (tenant_id, expedicao_id).
-- Refresh: incremental merge com lookback de 2 dias em updated_at.
-- FKs: transportadora_id -> silver_dw_transportadoras, venda_id -> silver_dw_vendas.

{{ config(
    unique_key = ['tenant_id', 'expedicao_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        expedicao_id,
        venda_id,
        transportadora_id,
        cast(dt_expedicao as date)                         as dt_expedicao,
        cast(dt_entrega_prevista as date)                  as dt_entrega_prevista,
        cast(dt_entrega_realizada as date)                 as dt_entrega_realizada,
        upper(trim(ds_status))                             as ds_status,
        cast(updated_at as timestamp(6))                   as updated_at,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, expedicao_id
            order by updated_at desc
        ) as _row_num
    from {{ source('bronze', 'expedicao') }}
    where expedicao_id is not null

    {% if is_incremental() %}
      and updated_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

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
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
