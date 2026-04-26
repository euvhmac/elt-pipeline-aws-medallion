-- silver_dw_lancamentos: lancamentos contabeis.
-- Grao: 1 linha por (tenant_id, lancamento_id).
-- FK plano_conta_id -> silver_dw_plano_contas.
-- Sem updated_at no Bronze — lookback por created_at.

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'lancamento_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with source as (

    select
        tenant_id,
        lancamento_id,
        plano_conta_id,
        upper(trim(cd_tipo_lancamento))             as cd_tipo_lancamento,
        cast(dt_competencia as date)                as dt_competencia,
        cast(vlr_lancamento as decimal(18, 2))      as vlr_lancamento,
        upper(trim(coalesce(historico, '')))        as ds_historico,
        created_at
    from {{ source('bronze', 'lancamentos') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    lancamento_id,
    plano_conta_id,
    cd_tipo_lancamento,
    dt_competencia,
    vlr_lancamento,
    ds_historico,
    created_at
from source
