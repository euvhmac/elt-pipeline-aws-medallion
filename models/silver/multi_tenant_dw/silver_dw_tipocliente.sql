
{{ config(
    unique_key='sk_tipo_cliente',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_tipocliente') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_tipocliente AS STRING)) AS sk_tipo_cliente,

        -- Identificadores (padronizados como STRING)
        CAST(id_tipocliente AS STRING) AS id_tipo_cliente,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(descricao, 'NÃO INFORMADO'))) AS descricao,

        -- Campos Numéricos
        COALESCE(TRY_CAST(percentual_comissao AS DECIMAL(17, 2)), 0) AS percentual_comissao,
        
        -- Metadados
        empresa,
        CAST(id_erp_internal AS STRING) AS id_erp_internal -- Mantendo o ID do sistema legado se necessário para rastreabilidade

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_tipo_cliente -- Particiona pela surrogate key para garantir unicidade
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