-- silver_dw_orcamento: limpeza + padronizacao dos registros de orcamento por projeto.
-- Grao: 1 linha por (tenant_id, orcamento_id).
-- Refresh: incremental merge com lookback de 2 dias em created_at.
-- FKs: projeto_id -> silver_dw_projetos, centro_custo_id -> silver_dw_centros_custos.

{{ config(
    unique_key = ['tenant_id', 'orcamento_id'],
    incremental_strategy = 'merge'
) }}

with source as (

    select
        tenant_id,
        orcamento_id,
        projeto_id,
        centro_custo_id,
        cast(competencia as date)                          as dt_competencia,
        cast(vlr_orcado as decimal(18, 2))                 as vlr_orcado,
        cast(vlr_realizado as decimal(18, 2))              as vlr_realizado,
        cast(created_at as timestamp(6))                   as created_at,
        current_timestamp                                  as _dbt_loaded_at,
        row_number() over (
            partition by tenant_id, orcamento_id
            order by created_at desc
        ) as _row_num
    from {{ source('bronze', 'orcamento') }}
    where orcamento_id is not null

    {% if is_incremental() %}
      and created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

)

select
    tenant_id,
    orcamento_id,
    projeto_id,
    centro_custo_id,
    dt_competencia,
    vlr_orcado,
    vlr_realizado,
    created_at,
    _dbt_loaded_at
from source
where _row_num = 1
