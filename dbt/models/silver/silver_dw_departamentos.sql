-- silver_dw_departamentos: limpeza + padronizacao do cadastro de departamentos.
-- Grao: 1 linha por (tenant_id, departamento_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: tabela Bronze estatica (DIM_STATIC) sem updated_at -> lookback por created_at.

{{ config(
    unique_key = ['tenant_id', 'departamento_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        departamento_id,
        upper(trim(nome))                                  as nm_departamento,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, departamento_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'departamentos') }}
    where departamento_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    departamento_id,
    nm_departamento,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
