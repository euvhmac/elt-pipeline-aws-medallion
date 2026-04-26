-- fct_orcamento_projetos: fato de orcamento por projeto e centro de custo.
-- Grao: 1 linha por (tenant_id, orcamento_id).
-- Campo calculado: vlr_delta = vlr_realizado - vlr_orcado (positivo = estouro).
-- FKs: centro_custo_sk -> dim_centros_custos, data_id -> dim_calendrio.

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'orcamento_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with orcamento as (

    select
        tenant_id,
        orcamento_id,
        projeto_id,
        centro_custo_id,
        dt_competencia,
        vlr_orcado,
        vlr_realizado,
        created_at
    from {{ ref('silver_dw_orcamento') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

centros as (

    select
        tenant_id,
        centro_custo_id,
        centro_custo_sk
    from {{ ref('dim_centros_custos') }}

),

joined as (

    select
        {{ dbt_utils.generate_surrogate_key(['o.tenant_id', 'o.orcamento_id']) }} as orcamento_sk,
        o.tenant_id,
        o.orcamento_id,
        o.projeto_id,
        c.centro_custo_sk,
        cast(date_format(o.dt_competencia, '%Y%m%d') as integer)  as data_id,
        o.vlr_orcado,
        o.vlr_realizado,
        -- positivo = estouro, negativo = economia
        cast(o.vlr_realizado - o.vlr_orcado as decimal(18, 2))    as vlr_delta,
        o.dt_competencia,
        o.created_at
    from orcamento o
    inner join centros c
        on o.tenant_id = c.tenant_id
        and o.centro_custo_id = c.centro_custo_id

)

select
    orcamento_sk,
    tenant_id,
    orcamento_id,
    projeto_id,
    centro_custo_sk,
    data_id,
    vlr_orcado,
    vlr_realizado,
    vlr_delta,
    dt_competencia,
    created_at
from joined
