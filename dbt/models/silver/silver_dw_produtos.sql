-- silver_dw_produtos: limpeza do catalogo de produtos.
-- Grao: 1 linha por (tenant_id, produto_id).

{{ config(
    unique_key = ['tenant_id', 'produto_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        produto_id,
        upper(trim(descricao))                  as dsc_produto,
        upper(trim(coalesce(categoria, 'NA')))  as nm_categoria,
        cast(preco_unitario as decimal(18, 2))  as vlr_preco_unitario,
        cast(created_at as timestamp(6))        as created_at,
        cast(updated_at as timestamp(6))        as updated_at,
        current_timestamp                       as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, produto_id
            order by updated_at desc
        ) as _row_num
    from {{ source('bronze', 'produtos') }}
    where produto_id is not null

    {% if is_incremental() %}
      and updated_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id, produto_id, dsc_produto, nm_categoria, vlr_preco_unitario,
    created_at, updated_at, _dbt_loaded_at
from source
where _row_num = 1
