-- silver_dw_projetos: limpeza + padronizacao do cadastro de projetos.
-- Grao: 1 linha por (tenant_id, projeto_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: sem updated_at -> lookback por created_at.

{{ config(
    unique_key = ['tenant_id', 'projeto_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        projeto_id,
        upper(trim(nome))                                  as nm_projeto,
        centro_custo_id,
        cast(dt_inicio as date)                            as dt_inicio,
        cast(dt_fim as date)                               as dt_fim,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, projeto_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'projetos') }}
    where projeto_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    projeto_id,
    nm_projeto,
    centro_custo_id,
    dt_inicio,
    dt_fim,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
