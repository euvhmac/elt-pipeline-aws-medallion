-- controle_inadimplentes: visao de titulos vencidos e nao baixados por unidade.
-- Grao: 1 linha por (tenant_id, titulo_id, tipo_titulo) vencido.
-- Filtro: ds_situacao_titulo = 'VENCIDO' (nao liquidados com data passada).
-- Camada Platinum: visao de negocio pronta para BI por unidade.

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

select
    tenant_id,
    titulo_id,
    tipo_titulo,
    entidade_id,
    dt_vencimento,
    vlr_titulo,
    nr_dias_atraso,
    data_id
from {{ ref('fct_titulo_financeiro') }}
where ds_situacao_titulo = 'VENCIDO'
