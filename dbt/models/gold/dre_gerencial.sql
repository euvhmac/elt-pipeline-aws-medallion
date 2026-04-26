-- dre_gerencial: DRE gerencial agrupada por categorias de negocio.
-- Grao: 1 linha por (tenant_id, empresa_id, centro_custo_id, ds_categoria, dt_competencia).
-- Agrupa cd_tipo_conta em categorias gerenciais (RECEITA/DESPESA/RESULTADO).
-- Materializada como table (snapshot mensal — nao incremental).

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with dre as (

    select
        tenant_id,
        empresa_id,
        centro_custo_id,
        centro_custo_sk,
        cd_tipo_conta,
        dt_competencia,
        data_id,
        vlr_total
    from {{ ref('dre_contabil') }}

),

categorizado as (

    select
        tenant_id,
        empresa_id,
        centro_custo_id,
        centro_custo_sk,
        dt_competencia,
        data_id,
        case cd_tipo_conta
            when 'RECEITA'  then 'RECEITA_BRUTA'
            when 'DESPESA'  then 'DESPESA_OPERACIONAL'
            when 'ATIVO'    then 'ATIVO_CIRCULANTE'
            when 'PASSIVO'  then 'PASSIVO_CIRCULANTE'
            else                 'OUTROS'
        end                                             as ds_categoria,
        vlr_total
    from dre

),

agrupado as (

    select
        tenant_id,
        empresa_id,
        centro_custo_id,
        centro_custo_sk,
        ds_categoria,
        dt_competencia,
        data_id,
        sum(vlr_total)                                  as vlr_categoria
    from categorizado
    group by
        tenant_id,
        empresa_id,
        centro_custo_id,
        centro_custo_sk,
        ds_categoria,
        dt_competencia,
        data_id

)

select
    {{ dbt_utils.generate_surrogate_key([
        'tenant_id', 'empresa_id', 'centro_custo_id', 'ds_categoria', 'dt_competencia'
    ]) }}                                               as dre_gerencial_sk,
    tenant_id,
    empresa_id,
    centro_custo_id,
    centro_custo_sk,
    ds_categoria,
    dt_competencia,
    data_id,
    cast(vlr_categoria as decimal(18, 2))               as vlr_categoria
from agrupado
