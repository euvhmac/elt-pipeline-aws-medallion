
{{ config(
    unique_key='sk_centro_custo',
    incremental_strategy='merge'
) }}

-- CTEs para carregar os dados de centros de custo de cada empresa
WITH unioned_sources AS (
    {{ union_sources('dw_ccusto_contabil') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_centro_custo AS STRING)) AS sk_centro_custo,

        -- Chave Estrangeira para Hierarquia (auto-relacionamento)
        CONCAT(empresa, '_', CAST(id_centro_custo_superior AS STRING)) AS sk_centro_custo_superior,

        -- Identificadores
        CAST(id_centro_custo AS STRING) AS id_centro_custo,
        CAST(id_empresa AS STRING) AS id_empresa_original,
        
        -- Dados Descritivos
        TRIM(UPPER(COALESCE(descricao, 'NÃO INFORMADO'))) AS descricao_centro_custo,
        TRIM(UPPER(COALESCE(tipo, 'NÃO INFORMADO'))) AS tipo, -- Ex: 'SINTETICO', 'ANALITICO'
        TRIM(UPPER(COALESCE(estrutura, ''))) AS estrutura_hierarquica,

        -- Níveis e Sequências
        CAST(grau AS INT) AS grau,
        CAST(sequencia_estrutura AS INT) AS sequencia_estrutura,

        -- Status
        (TRIM(UPPER(ativo)) = 'S') AS is_ativo, -- Converte 'S'/'N' para true/false
        
        -- Metadados
        empresa

    FROM unioned_sources
    WHERE id_centro_custo IS NOT NULL
),

-- Remove duplicatas
deduplicated AS (
    SELECT
        sk_centro_custo,
        sk_centro_custo_superior,
        id_centro_custo,
        id_empresa_original,
        descricao_centro_custo,
        tipo,
        estrutura_hierarquica,
        grau,
        sequencia_estrutura,
        is_ativo,
        empresa,
        ROW_NUMBER() OVER (
            PARTITION BY sk_centro_custo -- Agrupa pela nossa chave única
            ORDER BY
                estrutura_hierarquica, -- Prioriza registros com estrutura preenchida
                descricao_centro_custo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1