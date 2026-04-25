-- depends_on: {{ ref('empresas_grupo') }}

{{ config(materialized='table') }}

WITH deduplicated AS (
    SELECT
        cast(id_empresa as string) as id_empresa,
        cast(nome_empresa as string) as nome_empresa,
        ROW_NUMBER() OVER (
            PARTITION BY id_empresa
            ORDER BY nome_empresa DESC
        ) AS rn
    FROM {{ ref('empresas_grupo') }}
)

SELECT
    id_empresa,
    nome_empresa
FROM deduplicated
WHERE rn = 1
