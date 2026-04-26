-- silver_dw_titulos_financeiros: UNION ALL de titulos a pagar e a receber.
-- Grao: 1 linha por (tenant_id, titulo_id, tipo_titulo).
-- Enriquecido com baixas (dt_baixa, vlr_baixado) via LEFT JOIN.
-- Campo ds_tipo_titulo discrimina 'PAGAR' vs 'RECEBER'.

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'titulo_id', 'tipo_titulo'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with pagar as (

    select
        tenant_id,
        titulo_id,
        'PAGAR'                     as tipo_titulo,
        fornecedor_id               as entidade_id,
        dt_emissao,
        dt_vencimento,
        vlr_titulo,
        created_at
    from {{ source('bronze', 'titulos_pagar') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

receber as (

    select
        tenant_id,
        titulo_id,
        'RECEBER'                   as tipo_titulo,
        cliente_id                  as entidade_id,
        dt_emissao,
        dt_vencimento,
        vlr_titulo,
        created_at
    from {{ source('bronze', 'titulos_receber') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

todos as (

    select * from pagar
    union all
    select * from receber

),

baixas as (

    select
        tenant_id,
        titulo_id,
        tipo_titulo,
        max(dt_baixa)               as dt_baixa,
        sum(vlr_baixado)            as vlr_baixado
    from {{ source('bronze', 'baixas') }}
    group by tenant_id, titulo_id, tipo_titulo

),

joined as (

    select
        t.tenant_id,
        t.titulo_id,
        t.tipo_titulo,
        t.entidade_id,
        t.dt_emissao,
        t.dt_vencimento,
        cast(t.vlr_titulo as decimal(18, 2))                        as vlr_titulo,
        b.dt_baixa,
        cast(coalesce(b.vlr_baixado, 0) as decimal(18, 2))         as vlr_baixado,
        t.created_at
    from todos t
    left join baixas b
        on t.tenant_id  = b.tenant_id
        and t.titulo_id = b.titulo_id
        and t.tipo_titulo = b.tipo_titulo

)

select
    tenant_id,
    titulo_id,
    tipo_titulo,
    entidade_id,
    dt_emissao,
    dt_vencimento,
    vlr_titulo,
    dt_baixa,
    vlr_baixado,
    created_at
from joined
