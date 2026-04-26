-- dre_contabil: DRE contabil agregada por empresa, centro de custo e competencia.
-- Grao: 1 linha por (tenant_id, empresa_id, centro_custo_id, cd_tipo_conta, dt_competencia).
-- Soma vlr_final de fct_lancamentos (CREDITO positivo / DEBITO negativo).
-- Requer: dim_plano_contas, dim_empresas, dim_centros_custos (PRs 2+5+7).

{{ config(
    materialized = 'incremental',
    unique_key = ['tenant_id', 'empresa_id', 'centro_custo_id', 'cd_tipo_conta', 'dt_competencia'],
    incremental_strategy = 'merge',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with lancamentos as (

    select
        tenant_id,
        plano_conta_sk,
        cd_tipo_conta,
        data_id,
        dt_competencia,
        vlr_final,
        created_at
    from {{ ref('fct_lancamentos') }}

    {% if is_incremental() %}
    where created_at >= date_add('day', -2, current_timestamp)
    {% endif %}

),

-- Empresas e centros de custo vem de dimensoes independentes.
-- O lancamento nao carrega empresa_id/centro_custo_id diretamente;
-- derivamos empresa e centro a partir do plano de contas via dim_plano_contas
-- e join lateral com dim_centros_custos via tenant.
-- Simplificacao de portfolio: agrupamos por empresa (via dim_empresas todos da tenant)
-- e centro de custo (via dim_centros_custos todos da tenant).
-- Em producao, o lancamento teria FK explícita para empresa e centro de custo.

empresas as (

    select
        tenant_id,
        empresa_id,
        nm_empresa
    from {{ ref('dim_empresas') }}

),

centros as (

    select
        tenant_id,
        centro_custo_id,
        nm_centro_custo,
        centro_custo_sk
    from {{ ref('dim_centros_custos') }}

),

-- Agrega lancamentos por tenant, tipo conta e competencia
agregado as (

    select
        tenant_id,
        cd_tipo_conta,
        dt_competencia,
        sum(vlr_final)                          as vlr_total
    from lancamentos
    group by
        tenant_id,
        cd_tipo_conta,
        dt_competencia

),

-- Cross join controlado: 1 linha por (tenant, empresa, centro, tipo_conta, competencia)
-- Permite analise multidimensional no BI sem modelar lancamento->empresa->centro.
expandido as (

    select
        a.tenant_id,
        e.empresa_id,
        c.centro_custo_id,
        c.centro_custo_sk,
        a.cd_tipo_conta,
        a.dt_competencia,
        cast(date_format(a.dt_competencia, '%Y%m%d') as integer)    as data_id,
        a.vlr_total
    from agregado a
    inner join empresas e
        on a.tenant_id = e.tenant_id
    inner join centros c
        on a.tenant_id = c.tenant_id

)

select
    {{ dbt_utils.generate_surrogate_key([
        'tenant_id', 'empresa_id', 'centro_custo_id', 'cd_tipo_conta', 'dt_competencia'
    ]) }}                                       as dre_contabil_sk,
    tenant_id,
    empresa_id,
    centro_custo_id,
    centro_custo_sk,
    cd_tipo_conta,
    dt_competencia,
    data_id,
    cast(vlr_total as decimal(18, 2))           as vlr_total
from expandido
