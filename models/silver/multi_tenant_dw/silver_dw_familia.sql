
{{ config(
    unique_key='sk_familia',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_familia') }}
),

-- Aplica a limpeza, padronização e tipagem das colunas
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_familia AS STRING)) AS sk_familia,

        -- Identificadores (padronizados como STRING)
        CAST(id_familia AS STRING) AS id_familia,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(familia_descricao, 'NÃO INFORMADO'))) AS descricao_familia,
        
        -- Metadados
        empresa,
        CAST(id_erp_internal AS STRING) AS id_erp_internal

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_familia -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                descricao_familia -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1