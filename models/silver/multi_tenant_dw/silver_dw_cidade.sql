

WITH unioned_sources AS (
    {{ union_sources('dw_cidade') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_cidade AS STRING)) AS sk_cidade,

        -- Identificadores (padronizados como STRING)
        CAST(id_cidade AS STRING) AS id_cidade,
        CAST(id_pais AS STRING) AS id_pais,
        CAST(codigo_municipio AS STRING) AS codigo_ibge_municipio, -- Renomeado para clareza

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(nome_cidade, 'NÃO INFORMADO'))) AS nome_cidade,
        TRIM(UPPER(COALESCE(estado, 'NI'))) AS sigla_uf, -- Renomeado para clareza

        -- Campos Numéricos
        CAST(COALESCE(cidade_populacao, 0) AS INT) AS populacao,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY empresa, id_cidade -- Apenas duplicatas na mesma empresa e mesmo ID
            ORDER BY
                nome_cidade -- Critério de desempate para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1