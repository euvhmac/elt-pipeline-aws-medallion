-- silver_dw_ordens_producao: limpeza + padronizacao das ordens de producao.
-- Grao: 1 linha por (tenant_id, ordem_producao_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: sem updated_at no Bronze -> lookback por created_at.
-- FK produto_id -> silver_dw_produtos (definido na Sprint 4).

{{ config(
    unique_key = ['tenant_id', 'ordem_producao_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        ordem_producao_id,
        produto_id,
        cast(qt_produzida as decimal(18, 4))               as qt_produzida,
        cast(dt_inicio as date)                            as dt_inicio,
        cast(dt_fim as date)                               as dt_fim,
        upper(trim(ds_status))                             as ds_status,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, ordem_producao_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'ordens_producao') }}
    where ordem_producao_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    ordem_producao_id,
    produto_id,
    qt_produzida,
    dt_inicio,
    dt_fim,
    ds_status,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
