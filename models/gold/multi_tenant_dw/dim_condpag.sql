-- depends_on: {{ ref('silver_dw_condpag') }}

{{ config(materialized='table') }}

WITH deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_condicao_pagamento
            ORDER BY descricao_condicao_pagamento DESC
        ) AS rn
    FROM {{ ref('silver_dw_condpag') }}
)

SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1