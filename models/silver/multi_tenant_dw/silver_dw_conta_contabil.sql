
{{ config(
    unique_key='sk_conta_contabil',
    incremental_strategy='merge'
) }}

-- CTEs para carregar os dados de contas contábeis de cada empresa
WITH unioned_sources AS (
    {{ union_sources('dw_conta_contabil') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_conta AS STRING)) AS sk_conta_contabil,

        -- Chave Estrangeira para Hierarquia (auto-relacionamento)
        CONCAT(empresa, '_', CAST(id_conta_superior AS STRING)) AS sk_conta_superior,

        -- Identificadores
        CAST(id_conta AS STRING) AS id_conta,
        CAST(id_empresa AS STRING) AS id_empresa_original,
        CAST(id_grupo_analitico AS STRING) AS id_grupo_analitico,
        
        -- Dados Descritivos
        TRIM(UPPER(COALESCE(descricao, 'NÃO INFORMADO'))) AS descricao_conta,
        TRIM(UPPER(COALESCE(grupo, 'NÃO INFORMADO'))) AS grupo_conta,
        TRIM(UPPER(COALESCE(tipo, 'NÃO INFORMADO'))) AS tipo_conta, -- Ex: 'SINTETICA', 'ANALITICA'
        TRIM(UPPER(COALESCE(natureza, 'NÃO INFORMADO'))) AS natureza_conta, -- Ex: 'DEVEDORA', 'CREDORA'
        TRIM(UPPER(COALESCE(estrutura, ''))) AS estrutura_hierarquica,
        TRIM(UPPER(COALESCE(tipo_saldo, ''))) AS tipo_saldo,

        -- Níveis e Sequências
        CAST(grau AS INT) AS grau,
        CAST(sequencia_estrutura AS INT) AS sequencia_estrutura,

        -- Flags
        (TRIM(UPPER(custo)) = 'S') AS is_custo,
        (TRIM(UPPER(imobilizado)) = 'S') AS is_imobilizado,
        
        -- Metadados
        empresa

    FROM unioned_sources
    WHERE id_conta IS NOT NULL
),

-- Remove duplicatas
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_conta_contabil -- Agrupa pela nossa chave única
            ORDER BY
                estrutura_hierarquica, -- Prioriza registros com estrutura preenchida
                descricao_conta
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1