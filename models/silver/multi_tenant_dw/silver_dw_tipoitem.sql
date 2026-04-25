
{{ config(
    unique_key='sk_tipo_item',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_tipoitem') }}
),

-- Aplica a limpeza, padronização e tipagem das colunas
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_tipoitem AS STRING)) AS sk_tipo_item,

        -- Identificadores (padronizados como STRING)
        CAST(id_tipoitem AS STRING) AS id_tipo_item,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(descricao_tipo, 'NÃO INFORMADO'))) AS descricao_tipo_item,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_tipo_item -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                descricao_tipo_item -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1