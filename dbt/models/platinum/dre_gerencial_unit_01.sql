-- dre_gerencial_unit_01: DRE gerencial filtrada para unit_01.

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
    ds_categoria,
    dt_competencia,
    data_id,
    vlr_categoria
from {{ ref('dre_gerencial') }}
where tenant_id = 'unit_01'
