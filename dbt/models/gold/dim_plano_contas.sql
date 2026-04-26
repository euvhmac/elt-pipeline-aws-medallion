-- dim_plano_contas: dimensao Iceberg type 1 do plano de contas.
-- Grao: 1 linha por (tenant_id, plano_conta_id).
-- OBRIGATORIO antes do PR 8 (dre_contabil).

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with source as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'plano_conta_id']) }} as plano_conta_sk,
        tenant_id,
        plano_conta_id,
        cd_conta,
        ds_conta,
        cd_tipo_conta,
        created_at
    from {{ ref('silver_dw_plano_contas') }}

)

select
    plano_conta_sk,
    tenant_id,
    plano_conta_id,
    cd_conta,
    ds_conta,
    cd_tipo_conta,
    created_at
from source
