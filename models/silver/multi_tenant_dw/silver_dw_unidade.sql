
{{ config(
    materialized='table',
    schema='silver__multi_tenant_dw'
) }}

-- CTEs para carregar os dados de unidades de cada empresa
WITH unioned_sources AS (
    {{ union_sources('dw_unidade') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key) da unidade - composta por empresa + id_empresa + id_unidade
        CONCAT(empresa, '_', CAST(id_empresa AS STRING), '_', CAST(id_unidade AS STRING)) AS sk_unidade,

        -- Chaves Estrangeiras (Surrogate Keys)
        CONCAT(empresa, '_', CAST(id_cidade AS STRING)) AS sk_cidade,
        CONCAT(empresa, '_', CAST(id_empresa AS STRING), '_', CAST(id_filial AS STRING)) AS sk_filial,
        
        -- Identificadores
        CAST(id_empresa AS STRING) AS id_empresa,
        CAST(id_unidade AS STRING) AS id_unidade,
        CAST(id_cidade AS STRING) AS id_cidade,
        CAST(id_filial AS STRING) AS id_filial,
        CAST(id_erp_internal AS STRING) AS id_erp_internal,

        -- Dados Descritivos
        TRIM(UPPER(COALESCE(unidade_nome, 'NÃO INFORMADO'))) AS nome_unidade,
        TRIM(UPPER(COALESCE(nome_fantasia, ''))) AS nome_fantasia,
        TRIM(UPPER(COALESCE(sigla, ''))) AS sigla_unidade,
        
        -- Metadados
        empresa

    FROM unioned_sources
    WHERE id_empresa IS NOT NULL AND id_unidade IS NOT NULL
),

-- Remove duplicatas
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY empresa, id_empresa, id_unidade -- Agrupa pela chave composta
            ORDER BY
                nome_unidade
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1