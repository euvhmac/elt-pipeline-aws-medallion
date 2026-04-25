
{{ config(
    unique_key='sk_rota',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_rota') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(codigo AS STRING)) AS sk_rota,

        -- Identificadores (padronizados como STRING)
        CAST(codigo AS STRING) AS id_rota,
        CAST(rota_principal AS STRING) AS id_rota_principal,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(descricao, 'NÃO INFORMADO'))) AS descricao,

        -- Campos Numéricos
        COALESCE(TRY_CAST(peso_minimo AS DECIMAL(17, 2)), 0) AS peso_minimo,
        CAST(sequencia AS INT) AS sequencia,

        -- Flags (Campos BIT convertidos para BOOLEAN)
        CASE WHEN rota_prioritaria = 1 THEN TRUE ELSE FALSE END AS is_rota_prioritaria,
        CASE WHEN balanca = 1 THEN TRUE ELSE FALSE END AS is_balanca,
        CASE WHEN rota_sequencial = 1 THEN TRUE ELSE FALSE END AS is_rota_sequencial,
        CASE WHEN redespacho = 1 THEN TRUE ELSE FALSE END AS is_redespacho,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_rota -- Particiona pela surrogate key para garantir unicidade
            ORDER BY
                descricao -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1