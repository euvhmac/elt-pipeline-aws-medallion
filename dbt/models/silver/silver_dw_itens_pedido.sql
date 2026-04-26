-- silver_dw_itens_pedido: itens normalizados (grao do fct_vendas).
-- Grao: 1 linha por (tenant_id, item_id).

{{ config(
    unique_key = ['tenant_id', 'item_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        item_id,
        venda_id,
        produto_id,
        cast(qtd_vendida as decimal(18, 4))  as qtd_vendida,
        cast(vlr_unitario as decimal(18, 2)) as vlr_unitario,
        cast(vlr_total as decimal(18, 2))    as vlr_total,
        cast(created_at as timestamp(6))     as created_at,
        current_timestamp                    as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, item_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'itens_pedido') }}
    where item_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id, item_id, venda_id, produto_id,
    qtd_vendida, vlr_unitario, vlr_total, created_at, _dbt_loaded_at
from source
where _row_num = 1
