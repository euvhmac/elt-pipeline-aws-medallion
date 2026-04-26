-- dim_centros_custos: dimensao Iceberg type 1 de centros de custo.
-- Grao: 1 linha por (tenant_id, centro_custo_id).
-- Dim plana — sem hierarquia no Bronze. Necessaria para DRE (PR 8).

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with source as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'centro_custo_id']) }} as centro_custo_sk,
        tenant_id,
        centro_custo_id,
        nm_centro_custo,
        created_at
    from {{ ref('silver_dw_centros_custos') }}

)

select
    centro_custo_sk,
    tenant_id,
    centro_custo_id,
    nm_centro_custo,
    created_at
from source
