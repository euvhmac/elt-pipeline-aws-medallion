-- silver_dw_ordens_compra: limpeza + padronizacao das ordens de compra.
-- Grao: 1 linha por (tenant_id, ordem_compra_id).
-- Refresh: incremental merge com lookback de 2 dias em updated_at.

{{ config(
    unique_key = ['tenant_id', 'ordem_compra_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        ordem_compra_id,
        fornecedor_id,
        cast(dt_emissao as date)                          as dt_emissao,
        cast(vlr_total as decimal(18, 2))                 as vlr_total,
        upper(trim(status))                               as ds_status,
        cast(created_at as timestamp(6))                  as created_at,
        cast(updated_at as timestamp(6))                  as updated_at,
        current_timestamp                                 as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, ordem_compra_id
            order by updated_at desc
        ) as _row_num
    from {{ source('bronze', 'ordens_compra') }}
    where ordem_compra_id is not null

    {% if is_incremental() %}
      and updated_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    ordem_compra_id,
    fornecedor_id,
    dt_emissao,
    vlr_total,
    ds_status,
    created_at,
    updated_at,
    _dbt_loaded_at
from source
where _row_num = 1
