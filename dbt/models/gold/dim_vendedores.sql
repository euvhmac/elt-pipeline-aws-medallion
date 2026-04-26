-- dim_vendedores: dimensao Kimball type 1 de vendedores.
-- Grao: 1 linha por (tenant_id, vendedor_id).

{{ config(
    materialized = 'table'
) }}

select
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'vendedor_id']) }} as vendedor_sk,
    tenant_id,
    vendedor_id,
    nm_vendedor,
    filial_id,
    created_at,
    updated_at,
    _dbt_loaded_at
from {{ ref('silver_dw_vendedores') }}
