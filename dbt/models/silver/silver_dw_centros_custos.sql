-- silver_dw_centros_custos: limpeza + padronizacao do cadastro de centros de custo.
-- Grao: 1 linha por (tenant_id, centro_custo_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: dim plana — sem hierarquia no Bronze. Sem updated_at -> lookback por created_at.
-- Necessario para DRE (PR 8) via join centro_custo_id.

{{ config(
    unique_key = ['tenant_id', 'centro_custo_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        centro_custo_id,
        upper(trim(nome))                                  as nm_centro_custo,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, centro_custo_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'centros_custos') }}
    where centro_custo_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    centro_custo_id,
    nm_centro_custo,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
