-- silver_dw_plano_contas: cadastro do plano de contas contabil.
-- Grao: 1 linha por (tenant_id, plano_conta_id).
-- Dim estatica — sem updated_at no Bronze. Lookback por created_at.
-- Campo cd_tipo_conta determina o tipo (ATIVO/PASSIVO/RECEITA/DESPESA).

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'plano_conta_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with source as (

    select
        tenant_id,
        plano_conta_id,
        upper(trim(codigo))         as cd_conta,
        upper(trim(descricao))      as ds_conta,
        upper(trim(tipo))           as cd_tipo_conta,
        created_at
    from {{ source('bronze', 'plano_contas') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    plano_conta_id,
    cd_conta,
    ds_conta,
    cd_tipo_conta,
    created_at
from source
