-- dim_funcionarios: dimensao Iceberg type 1 de funcionarios.
-- Grao: 1 linha por (tenant_id, funcionario_id).
-- nm_departamento desnormalizado via join para facilitar analise BI.

{{ config(
    materialized = 'table',
    table_type = 'iceberg',
    format = 'parquet',
    partitioned_by = ['tenant_id']
) }}

with funcionarios as (

    select
        tenant_id,
        funcionario_id,
        nm_funcionario,
        departamento_id,
        ds_cargo,
        dt_admissao,
        created_at
    from {{ ref('silver_dw_funcionarios') }}

),

departamentos as (

    select
        tenant_id,
        departamento_id,
        nm_departamento
    from {{ ref('silver_dw_departamentos') }}

),

joined as (

    select
        {{ dbt_utils.generate_surrogate_key(['f.tenant_id', 'f.funcionario_id']) }} as funcionario_sk,
        f.tenant_id,
        f.funcionario_id,
        f.nm_funcionario,
        f.departamento_id,
        coalesce(d.nm_departamento, 'NAO_INFORMADO')       as nm_departamento,
        f.ds_cargo,
        f.dt_admissao,
        f.created_at
    from funcionarios f
    left join departamentos d
        on f.tenant_id = d.tenant_id
        and f.departamento_id = d.departamento_id

)

select
    funcionario_sk,
    tenant_id,
    funcionario_id,
    nm_funcionario,
    departamento_id,
    nm_departamento,
    ds_cargo,
    dt_admissao,
    created_at
from joined
