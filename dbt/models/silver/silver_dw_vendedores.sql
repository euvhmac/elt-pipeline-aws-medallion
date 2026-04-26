-- silver_dw_vendedores: limpeza do cadastro de vendedores.
-- Grao: 1 linha por (tenant_id, vendedor_id).

{{ config(
    unique_key = ['tenant_id', 'vendedor_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        vendedor_id,
        upper(trim(nome))                  as nm_vendedor,
        filial_id,
        cast(created_at as timestamp(6))   as created_at,
        cast(updated_at as timestamp(6))   as updated_at,
        current_timestamp                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, vendedor_id
            order by updated_at desc
        ) as _row_num
    from {{ source('bronze', 'vendedores') }}
    where vendedor_id is not null

    {% if is_incremental() %}
      and updated_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id, vendedor_id, nm_vendedor, filial_id,
    created_at, updated_at, _dbt_loaded_at
from source
where _row_num = 1
