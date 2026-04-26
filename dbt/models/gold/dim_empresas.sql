-- dim_empresas: dimensao Iceberg type 1 de empresas.
-- Grao: 1 linha por (tenant_id, empresa_id).
-- Necessario para DRE (PR 8) via join empresa_id.

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with source as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'empresa_id']) }} as empresa_sk,
        tenant_id,
        empresa_id,
        nm_empresa,
        nr_documento,
        created_at
    from {{ ref('silver_dw_empresas') }}

)

select
    empresa_sk,
    tenant_id,
    empresa_id,
    nm_empresa,
    nr_documento,
    created_at
from source
