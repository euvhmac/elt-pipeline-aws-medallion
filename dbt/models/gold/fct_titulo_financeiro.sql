-- fct_titulo_financeiro: fato de titulos a pagar e receber.
-- Grao: 1 linha por (tenant_id, titulo_id, tipo_titulo).
-- Campo ds_situacao_titulo: LIQUIDADO / VENCIDO / EM_ABERTO.
-- Campo nr_dias_atraso: dias de atraso para titulos vencidos (0 para os demais).
-- OBRIGATORIO antes do PR 9 (Platinum: controle_inadimplentes).

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'titulo_id', 'tipo_titulo'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with source as (

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
    from {{ ref('silver_dw_titulos_financeiros') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

enriched as (

    select
        {{ dbt_utils.generate_surrogate_key(['tenant_id', 'titulo_id', 'tipo_titulo']) }} as titulo_sk,
        tenant_id,
        titulo_id,
        tipo_titulo,
        entidade_id,
        dt_emissao,
        dt_vencimento,
        vlr_titulo,
        dt_baixa,
        vlr_baixado,
        -- situacao calculada em tempo de leitura
        case
            when dt_baixa is not null                        then 'LIQUIDADO'
            when dt_vencimento < current_date               then 'VENCIDO'
            else                                                 'EM_ABERTO'
        end                                                 as ds_situacao_titulo,
        -- dias de atraso: apenas para vencidos sem baixa
        case
            when dt_baixa is null and dt_vencimento < current_date
                then date_diff('day', dt_vencimento, current_date)
            else 0
        end                                                 as nr_dias_atraso,
        cast(date_format(dt_vencimento, '%Y%m%d') as integer) as data_id,
        created_at
    from source

)

select
    titulo_sk,
    tenant_id,
    titulo_id,
    tipo_titulo,
    entidade_id,
    dt_emissao,
    dt_vencimento,
    vlr_titulo,
    dt_baixa,
    vlr_baixado,
    ds_situacao_titulo,
    nr_dias_atraso,
    data_id,
    created_at
from enriched
