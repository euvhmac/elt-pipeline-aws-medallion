-- dim_produtos: dimensao Kimball type 1 de produtos.
-- Grao: 1 linha por (tenant_id, produto_id).

{{ config(
    materialized = 'table'
) }}

select
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'produto_id']) }} as produto_sk,
    tenant_id,
    produto_id,
    dsc_produto,
    nm_categoria,
    vlr_preco_unitario,
    created_at,
    updated_at,
    _dbt_loaded_at
from {{ ref('silver_dw_produtos') }}
