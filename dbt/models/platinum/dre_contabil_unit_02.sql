-- dre_contabil_unit_02: DRE contabil filtrada para unit_02.
-- Visao de negocio pronta para BI da unidade 02.

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

select
    tenant_id,
    empresa_id,
    centro_custo_id,
    centro_custo_sk,
    cd_tipo_conta,
    dt_competencia,
    data_id,
    vlr_total
from {{ ref('dre_contabil') }}
where tenant_id = 'unit_02'
