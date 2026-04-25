-- depends_on: {{ source('bronze__unit_01', 'dw_empresa') }}
-- depends_on: {{ source('bronze__unit_02', 'dw_empresa') }}
-- depends_on: {{ source('bronze__unit_03', 'dw_empresa') }}
-- depends_on: {{ source('bronze__unit_04', 'dw_empresa') }}
-- depends_on: {{ source('bronze__unit_05', 'dw_empresa') }}

WITH unit_01 AS (
    SELECT
        try_cast(nullif(trim(id_erp_internal), '') as integer) as id_erp_internal,
        try_cast(nullif(trim(id_empresa), '') as integer) as id_empresa,
        trim(empresa_nome) as nome_empresa,
        trim(empresa_fantasia) as nome_fantasia,
        'Unit_01' as empresa
    FROM {{ source('bronze__unit_01', 'dw_empresa') }}
    WHERE id_empresa is not null
),
unit_02 AS (
    SELECT
        try_cast(nullif(trim(id_erp_internal), '') as integer) as id_erp_internal,
        try_cast(nullif(trim(id_empresa), '') as integer) as id_empresa,
        trim(empresa_nome) as nome_empresa,
        trim(empresa_fantasia) as nome_fantasia,
        'Unit_02' as empresa
    FROM {{ source('bronze__unit_02', 'dw_empresa') }}
    WHERE id_empresa is not null
),
unit_03 AS (
    SELECT
        try_cast(nullif(trim(id_erp_internal), '') as integer) as id_erp_internal,
        try_cast(nullif(trim(id_empresa), '') as integer) as id_empresa,
        trim(empresa_nome) as nome_empresa,
        trim(empresa_fantasia) as nome_fantasia,
        'Unit_03' as empresa
    FROM {{ source('bronze__unit_03', 'dw_empresa') }}
    WHERE id_empresa is not null
),
unit_04 AS (
    SELECT
        try_cast(nullif(trim(id_erp_internal), '') as integer) as id_erp_internal,
        try_cast(nullif(trim(id_empresa), '') as integer) as id_empresa,
        trim(empresa_nome) as nome_empresa,
        trim(empresa_fantasia) as nome_fantasia,
        'Unit_04' as empresa
    FROM {{ source('bronze__unit_04', 'dw_empresa') }}
    WHERE id_empresa is not null
),
unit_05 AS (
    SELECT
        try_cast(nullif(trim(id_erp_internal), '') as integer) as id_erp_internal,
        try_cast(nullif(trim(id_empresa), '') as integer) as id_empresa,
        trim(empresa_nome) as nome_empresa,
        trim(empresa_fantasia) as nome_fantasia,
        'Unit_05' as empresa
    FROM {{ source('bronze__unit_05', 'dw_empresa') }}
    WHERE id_empresa is not null
)

SELECT * FROM unit_01
UNION ALL
SELECT * FROM unit_02
UNION ALL
SELECT * FROM unit_03
UNION ALL
SELECT * FROM unit_04
UNION ALL
SELECT * FROM unit_05