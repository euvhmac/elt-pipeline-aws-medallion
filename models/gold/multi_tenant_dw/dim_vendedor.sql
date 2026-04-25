-- depends_on: {{ ref('silver_dw_vendedor') }}

{{ config(materialized='table') }}

WITH deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_vendedor
            ORDER BY empresa, nome_vendedor DESC
        ) AS rn
    FROM {{ ref('silver_dw_vendedor') }}
)

SELECT
    sk_vendedor,
    id_vendedor,
    id_vendedor_supervisor,
    id_funcionario,
    id_empresa,
    id_filial,
    nome_vendedor,
    cpf_cnpj,
    tipo_vendedor,
    percentual_comissao,
    empresa
FROM deduplicated
WHERE rn = 1