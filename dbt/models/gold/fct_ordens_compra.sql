-- fct_ordens_compra: fato transacional de ordens de compra.
-- Grao: 1 linha = 1 ordem de compra.
-- Granularidade: tenant_id x ordem_compra_id.
-- Refresh: incremental merge com lookback de 2 dias em dt_emissao.

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'ordem_compra_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    partitioned_by = ['tenant_id']
) }}

with ordens as (
    select * from {{ ref('silver_dw_ordens_compra') }}
),

fornecedores as (
    select * from {{ ref('silver_dw_fornecedores') }}
)

select
    -- chaves
    {{ dbt_utils.generate_surrogate_key(['ordens.tenant_id', 'ordens.ordem_compra_id']) }} as ordem_compra_sk,
    ordens.tenant_id,
    ordens.ordem_compra_id,

    -- foreign keys (surrogate)
    {{ dbt_utils.generate_surrogate_key(['ordens.tenant_id', 'ordens.fornecedor_id']) }} as fornecedor_sk,
    cast(date_format(ordens.dt_emissao, '%Y%m%d') as integer)                            as data_id,

    -- degenerate dimensions
    ordens.fornecedor_id,
    ordens.ds_status,

    -- metricas
    ordens.vlr_total,

    -- timestamps
    ordens.dt_emissao,
    ordens.created_at,
    current_timestamp as _dbt_loaded_at

from ordens
inner join fornecedores
    on ordens.tenant_id    = fornecedores.tenant_id
   and ordens.fornecedor_id = fornecedores.fornecedor_id

{% if is_incremental() %}
where ordens.dt_emissao >= cast(date_add('day', -2, current_timestamp) as date)
{% endif %}
