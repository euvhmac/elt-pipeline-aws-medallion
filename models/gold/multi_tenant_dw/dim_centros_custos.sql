-- depends_on: {{ ref('silver_dw_ccusto_contabil') }}

{{ config(materialized='table') }}

-- CTE para a tabela Silver de centros de custo
WITH stg_centros_custo AS (
    SELECT * FROM {{ ref('silver_dw_ccusto_contabil') }}
),

-- Realiza um auto-relacionamento para buscar a descrição do centro de custo superior
final AS (
    SELECT
        cc.sk_centro_custo,
        cc.id_centro_custo,
        cc.descricao_centro_custo,
        cc.tipo,
        cc.estrutura_hierarquica,
        cc.grau,
        cc.is_ativo,
        
        -- Hierarquia
        cc.sk_centro_custo_superior,
        superior.descricao_centro_custo AS descricao_centro_custo_superior,
        
        -- Metadados
        cc.empresa,

        -- Deduplicação
        ROW_NUMBER() OVER (
            PARTITION BY cc.sk_centro_custo
            ORDER BY cc.grau DESC, cc.descricao_centro_custo DESC
        ) AS rn

    FROM stg_centros_custo AS cc

    LEFT JOIN stg_centros_custo AS superior
        ON cc.sk_centro_custo_superior = superior.sk_centro_custo
)

SELECT
    * EXCEPT (rn)
FROM final
WHERE rn = 1