-- silver_dw_clientes: limpeza + padronizacao do cadastro de clientes.
-- Grao: 1 linha por (tenant_id, cliente_id).
-- Refresh: incremental merge com lookback de 2 dias em updated_at.

{{ config(
    unique_key = ['tenant_id', 'cliente_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        cliente_id,
        upper(trim(nome))                                  as nm_cliente,
        regexp_replace(coalesce(documento, ''), '[^0-9]')  as nr_documento,
        lower(trim(email))                                 as ds_email,
        upper(trim(cidade))                                as nm_cidade,
        upper(trim(uf))                                    as cd_uf,
        cast(created_at as timestamp(6))                   as created_at,
        cast(updated_at as timestamp(6))                   as updated_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, cliente_id
            order by updated_at desc
        ) as _row_num
    from {{ source('bronze', 'clientes') }}
    where cliente_id is not null

    {% if is_incremental() %}
      and updated_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    cliente_id,
    nm_cliente,
    nr_documento,
    ds_email,
    nm_cidade,
    cd_uf,
    created_at,
    updated_at,
    _dbt_loaded_at
from source
where _row_num = 1
