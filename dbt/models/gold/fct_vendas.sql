-- fct_vendas: fato transacional de vendas.
-- Grao: 1 linha = 1 item de pedido (split de venda).
-- Granularidade: tenant_id x venda_id x item_id.
-- Refresh: incremental merge com lookback de 2 dias em dt_venda.

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'item_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    partitioned_by = ['tenant_id']
) }}

with itens as (
    select * from {{ ref('silver_dw_itens_pedido') }}
),

vendas as (
    select * from {{ ref('silver_dw_vendas') }}
)

select
    -- chaves
    {{ dbt_utils.generate_surrogate_key(['itens.tenant_id', 'itens.item_id']) }} as venda_item_sk,
    itens.tenant_id,
    itens.item_id,
    itens.venda_id,

    -- foreign keys (surrogate)
    {{ dbt_utils.generate_surrogate_key(['itens.tenant_id', 'vendas.cliente_id']) }}    as cliente_sk,
    {{ dbt_utils.generate_surrogate_key(['itens.tenant_id', 'vendas.vendedor_id']) }}   as vendedor_sk,
    {{ dbt_utils.generate_surrogate_key(['itens.tenant_id', 'itens.produto_id']) }}     as produto_sk,
    cast(date_format(vendas.dt_venda, '%Y%m%d') as integer)                              as data_id,

    -- degenerate dimensions (mantidas para auditoria)
    vendas.cliente_id,
    vendas.vendedor_id,
    itens.produto_id,
    vendas.ds_status,

    -- metricas
    itens.qtd_vendida,
    itens.vlr_unitario,
    itens.vlr_total,

    -- timestamps
    vendas.dt_venda,
    itens.created_at,
    current_timestamp as _dbt_loaded_at

from itens
inner join vendas
    on itens.tenant_id = vendas.tenant_id
   and itens.venda_id  = vendas.venda_id

{% if is_incremental() %}
where vendas.dt_venda >= date_add('day', -2, current_timestamp)
{% endif %}
