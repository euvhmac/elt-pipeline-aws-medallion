
{{ config(
    unique_key='sk_filial',
    incremental_strategy='merge'
) }}

-- CTEs para carregar os dados de filiais de cada empresa
WITH unioned_sources AS (
    {{ union_sources('dw_filial') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key) da filial
        CONCAT(empresa, '_', CAST(id_filial AS STRING)) AS sk_filial,

        -- Chaves Estrangeiras (Surrogate Keys)
        CONCAT(empresa, '_', CAST(id_cidade AS STRING)) AS sk_cidade,
        
        -- Identificadores
        CAST(id_filial AS STRING) AS id_filial,
        CAST(id_empresa AS STRING) AS id_empresa_original,
        NULLIF(REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', ''), '') AS cnpj,

        -- Dados Descritivos
        TRIM(UPPER(COALESCE(filial_nome, 'NÃO INFORMADO'))) AS nome_filial,
        TRIM(UPPER(COALESCE(nome_fantasia, ''))) AS nome_fantasia,
        TRIM(UPPER(COALESCE(sigla, ''))) AS sigla_filial,
        
        -- Metadados
        empresa,
        CAST(id_erp_internal AS STRING) AS id_erp_internal

    FROM unioned_sources
    WHERE id_filial IS NOT NULL
),

-- Remove duplicatas
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_filial -- Agrupa pela nossa chave única
            ORDER BY
                nome_filial
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1