-- silver_dw_materias_primas: limpeza + padronizacao do cadastro de materias-primas.
-- Grao: 1 linha por (tenant_id, materia_prima_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: tabela Bronze estatica (DIM_STATIC) sem updated_at -> lookback por created_at.

{{ config(
    unique_key = ['tenant_id', 'materia_prima_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        materia_prima_id,
        upper(trim(nome))                                  as nm_materia_prima,
        upper(trim(unidade_medida))                        as ds_unidade_medida,
        cast(preco_unitario as decimal(18, 4))             as vlr_preco_unitario,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, materia_prima_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'materias_primas') }}
    where materia_prima_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    materia_prima_id,
    nm_materia_prima,
    ds_unidade_medida,
    vlr_preco_unitario,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
