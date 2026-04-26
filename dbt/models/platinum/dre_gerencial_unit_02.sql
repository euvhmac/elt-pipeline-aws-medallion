-- dre_gerencial_unit_02: DRE gerencial filtrada para unit_02.

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
where tenant_id = 'unit_02'
