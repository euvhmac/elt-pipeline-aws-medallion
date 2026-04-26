-- silver_dw_filiais: limpeza + padronizacao do cadastro de filiais.
-- Grao: 1 linha por (tenant_id, filial_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: tabela Bronze estatica (DIM_STATIC) sem updated_at -> lookback por created_at.

{{ config(
    unique_key = ['tenant_id', 'filial_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        filial_id,
        upper(trim(nome))                                  as nm_filial,
        upper(trim(cidade))                                as nm_cidade,
        upper(trim(uf))                                    as sg_uf,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, filial_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'filiais') }}
    where filial_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    filial_id,
    nm_filial,
    nm_cidade,
    sg_uf,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
