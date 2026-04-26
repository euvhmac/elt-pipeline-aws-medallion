-- dim_fornecedores: dimensao Kimball type 1 de fornecedores.
-- Grao: 1 linha por (tenant_id, fornecedor_id).
-- Surrogate key fornecedor_sk = hash(tenant_id, fornecedor_id).

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    partitioned_by = ['tenant_id']
) }}

select
    {{ dbt_utils.generate_surrogate_key(['tenant_id', 'fornecedor_id']) }} as fornecedor_sk,
    tenant_id,
    fornecedor_id,
    nm_fornecedor,
    nr_documento,
    created_at,
    _dbt_loaded_at
from {{ ref('silver_dw_fornecedores') }}
