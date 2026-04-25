
{{ config(
    unique_key='sk_ramo',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_ramo') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_ramo AS STRING)) AS sk_ramo,

        -- Identificadores (padronizados como STRING)
        CAST(id_ramo AS STRING) AS id_ramo,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(ramo_atividade, 'NÃO INFORMADO'))) AS ramo_atividade,
        
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
            PARTITION BY sk_ramo -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                ramo_atividade -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1