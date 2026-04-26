-- fct_ordens_producao: fato transacional de ordens de producao.
-- Grao: 1 linha por (tenant_id, ordem_producao_id).
-- Campo calculado: dias_producao via date_diff (Trino/Athena v3).
-- FK produto_sk -> dim_produtos, data_id -> dim_calendrio.
-- dt_fim pode ser NULL para ordens em andamento (COALESCE com current_date).

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'ordem_producao_id'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with ordens as (

    select
        tenant_id,
        ordem_producao_id,
        produto_id,
        qt_produzida,
        dt_inicio,
        dt_fim,
        ds_status,
        created_at
    from {{ ref('silver_dw_ordens_producao') }}

    {% if is_incremental() %}
    where dt_inicio >= cast(date_add('day', -2, current_timestamp) as date)
    {% endif %}

),

produtos as (

    select
        tenant_id,
        produto_id,
        produto_sk
    from {{ ref('dim_produtos') }}

),

joined as (

    select
        {{ dbt_utils.generate_surrogate_key(['o.tenant_id', 'o.ordem_producao_id']) }} as ordem_producao_sk,
        o.tenant_id,
        o.ordem_producao_id,
        p.produto_sk,
        cast(date_format(o.dt_inicio, '%Y%m%d') as integer)  as data_id,
        o.qt_produzida,
        -- dias em producao: dt_fim ou current_date para ordens em andamento
        date_diff('day', o.dt_inicio, coalesce(o.dt_fim, current_date)) as nr_dias_producao,
        o.dt_inicio,
        o.dt_fim,
        o.ds_status,
        o.created_at
    from ordens o
    inner join produtos p
        on o.tenant_id = p.tenant_id
        and o.produto_id = p.produto_id

)

select
    ordem_producao_sk,
    tenant_id,
    ordem_producao_id,
    produto_sk,
    data_id,
    qt_produzida,
    nr_dias_producao,
    dt_inicio,
    dt_fim,
    ds_status,
    created_at
from joined
