-- silver_dw_vendas: cabecalho de vendas limpo.
-- Grao: 1 linha por (tenant_id, venda_id).
-- Refresh: incremental merge com lookback de 2 dias em dt_venda.

{{ config(
    unique_key = ['tenant_id', 'venda_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        venda_id,
        cast(dt_venda as timestamp(6))      as dt_venda,
        cliente_id,
        vendedor_id,
        cast(vlr_total as decimal(18, 2))   as vlr_total,
        upper(trim(status))                 as ds_status,
        cast(created_at as timestamp(6))    as created_at,
        cast(updated_at as timestamp(6))    as updated_at,
        current_timestamp                   as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, venda_id
            order by updated_at desc
        ) as _row_num
    from {{ source('bronze', 'vendas') }}
    where venda_id is not null

    {% if is_incremental() %}
      and dt_venda >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id, venda_id, dt_venda, cliente_id, vendedor_id,
    vlr_total, ds_status, created_at, updated_at, _dbt_loaded_at
from source
where _row_num = 1
