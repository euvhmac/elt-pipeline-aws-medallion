-- depends_on: {{ ref('silver_dw_conta_contabil') }}

{{ config(materialized='table') }}

-- CTE para a tabela Silver de contas contábeis
WITH stg_contas_contabeis AS (
    SELECT * FROM {{ ref('silver_dw_conta_contabil') }}
),

-- Realiza um auto-relacionamento para buscar a descrição da conta superior
final AS (
    SELECT
        conta.sk_conta_contabil,
        conta.id_conta,
        conta.descricao_conta,
        conta.grupo_conta,
        conta.tipo_conta,
        conta.natureza_conta,
        conta.estrutura_hierarquica,
        conta.grau,
        conta.is_custo,
        conta.is_imobilizado,
        
        -- Hierarquia
        conta.sk_conta_superior,
        superior.descricao_conta AS descricao_conta_superior,
        
        -- Metadados
        conta.empresa,

        -- Deduplicação
        ROW_NUMBER() OVER (
            PARTITION BY conta.sk_conta_contabil
            ORDER BY conta.grau DESC, conta.descricao_conta DESC
        ) AS rn

    FROM stg_contas_contabeis AS conta

    LEFT JOIN stg_contas_contabeis AS superior
        ON conta.sk_conta_superior = superior.sk_conta_contabil
)

SELECT
    * EXCEPT (rn)
FROM final
WHERE rn = 1