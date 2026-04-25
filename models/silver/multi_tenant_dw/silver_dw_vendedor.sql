
{{
    config(
        materialized='incremental',
        unique_key='sk_vendedor',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH unioned_sources AS (
    {{ union_sources('dw_vendedor') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_empresa AS STRING), '_', CAST(id_vendedor AS STRING)) AS sk_vendedor,

        -- Identificadores e Chaves (padronizados como STRING)
        CAST(id_vendedor AS STRING) AS id_vendedor,
        CAST(id_vendedor_sup AS STRING) AS id_vendedor_supervisor,
        CAST(id_funcionario AS STRING) AS id_funcionario,
        CAST(id_empresa AS STRING) AS id_empresa,
        CAST(id_filial AS STRING) AS id_filial,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(nome_vendedor, 'NÃO INFORMADO'))) AS nome_vendedor,
        NULLIF(REGEXP_REPLACE(COALESCE(cpfcnpj, ''), '[^0-9]', ''), '') AS cpf_cnpj,

        -- Classificação do Vendedor (exemplo de tratamento de campo de tipo)
        CASE 
            WHEN vendedor_tipo = 1 THEN 'TIPO 1 - PRINCIPAL' -- Mapear conforme regra de negócio
            WHEN vendedor_tipo = 2 THEN 'TIPO 2 - SECUNDÁRIO'
            ELSE 'OUTROS'
        END AS tipo_vendedor,

        -- Campos Numéricos
        COALESCE(TRY_CAST(percentual_comissao AS DECIMAL(17, 2)), 0) AS percentual_comissao,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa (apenas para registros com ID válido)
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_vendedor
            ORDER BY LENGTH(nome_vendedor) DESC, nome_vendedor DESC, empresa, id_vendedor -- Prioriza nomes mais longos/completos, depois alfabético, empresa e ID
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados desduplicados
-- O DBT com merge strategy já cuida de comparar com dados existentes via unique_key
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1