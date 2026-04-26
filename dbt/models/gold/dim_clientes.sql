-- dim_clientes: dimensao Kimball type 1 de clientes.
-- Grao: 1 linha por (tenant_id, cliente_id).
-- Surrogate key cliente_sk = hash(tenant_id, cliente_id).

{{ config(
    materialized = 'table'
) }}

select
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'cliente_id']) }} as cliente_sk,
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
from {{ ref('silver_dw_clientes') }}
