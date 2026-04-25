
WITH unioned_sources AS (
    {{ union_sources('dw_rede') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_rede AS STRING)) AS sk_rede,

        -- Identificadores (padronizados como STRING)
        CAST(id_rede AS STRING) AS id_rede,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(nome_rede, 'NÃO INFORMADO'))) AS nome_rede,
        
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
            PARTITION BY empresa, id_rede -- Apenas duplicatas na mesma empresa e mesmo ID
            ORDER BY
                nome_rede -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1