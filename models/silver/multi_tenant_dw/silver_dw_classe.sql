
{{ config(
    unique_key='sk_classe',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_classe') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_classe AS STRING)) AS sk_classe,

        -- Identificadores (padronizados como STRING)
        CAST(id_classe AS STRING) AS id_classe,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(classe_descricao, 'NÃO INFORMADO'))) AS descricao_classe,
        TRIM(UPPER(COALESCE(sigla, 'NI'))) AS sigla_classe,
        
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
            PARTITION BY sk_classe -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                descricao_classe -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1