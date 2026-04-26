-- dim_produtos_otimizada: subset de dim_produtos otimizado para BI.
-- Remove colunas tecnicas (_dbt_loaded_at, updated_at) nao uteis para BI.
-- Visao de negocio da camada Platinum.

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

select
    tenant_id,
    produto_id,
    dsc_produto,
    nm_categoria,
    vlr_preco_unitario,
    created_at
from {{ ref('dim_produtos') }}
