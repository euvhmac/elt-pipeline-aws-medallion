
{{ config(
    unique_key='sk_embalagem',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_embalagem') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_embalagem AS STRING)) AS sk_embalagem,

        -- Identificadores (padronizados como STRING)
        CAST(id_embalagem AS STRING) AS id_embalagem,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(nome_embalagem, 'NÃO INFORMADO'))) AS nome_embalagem,
        TRIM(UPPER(COALESCE(desc_complementar, ''))) AS descricao_complementar,

        -- Medidas e Capacidade (padronizados como DECIMAL)
        COALESCE(TRY_CAST(peso_embala AS DECIMAL(17, 2)), 0) AS peso_embalagem,
        COALESCE(TRY_CAST(capacidade AS DECIMAL(17, 2)), 0) AS capacidade,
        COALESCE(TRY_CAST(altura AS DECIMAL(17, 2)), 0) AS altura,
        COALESCE(TRY_CAST(comprimento AS DECIMAL(17, 2)), 0) AS comprimento,
        COALESCE(TRY_CAST(largura AS DECIMAL(17, 2)), 0) AS largura,

        -- Classificação
        CASE 
            WHEN tipo_embala = 1 THEN 'PRIMÁRIA'
            WHEN tipo_embala = 2 THEN 'SECUNDÁRIA'
            WHEN tipo_embala = 3 THEN 'TERCIÁRIA'
            ELSE 'NÃO DEFINIDO'
        END AS tipo_embalagem,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_embalagem -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                nome_embalagem -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1