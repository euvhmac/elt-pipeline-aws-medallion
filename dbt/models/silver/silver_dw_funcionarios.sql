-- silver_dw_funcionarios: limpeza + padronizacao do cadastro de funcionarios.
-- Grao: 1 linha por (tenant_id, funcionario_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- Nota: tabela Bronze estatica (DIM_STATIC) sem updated_at -> lookback por created_at.
-- FK departamento_id -> silver_dw_departamentos.

{{ config(
    unique_key = ['tenant_id', 'funcionario_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        funcionario_id,
        upper(trim(nome))                                  as nm_funcionario,
        departamento_id,
        upper(trim(cargo))                                 as ds_cargo,
        cast(dt_admissao as date)                          as dt_admissao,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, funcionario_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'funcionarios') }}
    where funcionario_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    funcionario_id,
    nm_funcionario,
    departamento_id,
    ds_cargo,
    dt_admissao,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
