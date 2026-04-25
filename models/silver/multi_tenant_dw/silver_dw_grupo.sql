
{{ config(
    unique_key='sk_grupo',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_grupo') }}
),

-- Aplica a limpeza, padronização e tipagem das colunas
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_grupo AS STRING)) AS sk_grupo,

        -- Identificadores (padronizados como STRING)
        CAST(id_grupo AS STRING) AS id_grupo,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(grupo_descricao, 'NÃO INFORMADO'))) AS descricao_grupo,
        
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
            PARTITION BY sk_grupo -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                descricao_grupo -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1