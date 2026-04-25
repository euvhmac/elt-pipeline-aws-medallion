
WITH unioned_sources AS (
    {{ union_sources('dw_item') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_item AS STRING)) AS sk_item,

        -- Chaves Estrangeiras (Surrogate Keys) para relacionamento com as dimensões
        -- Usando CASE para retornar NULL quando o ID for NULL
        CASE 
            WHEN id_grupo IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_grupo AS STRING))
            ELSE NULL 
        END AS sk_grupo,
        
        CASE 
            WHEN id_classe IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_classe AS STRING))
            ELSE NULL 
        END AS sk_classe,
        
        CASE 
            WHEN id_tipoitem IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_tipoitem AS STRING))
            ELSE NULL 
        END AS sk_tipo_item,
        
        CASE 
            WHEN id_marca_item IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_marca_item AS STRING))
            ELSE NULL 
        END AS sk_marca_item,
        
        CASE 
            WHEN id_areageo IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_areageo AS STRING))
            ELSE NULL 
        END AS sk_area_geografica,
        
        CASE 
            WHEN id_familia IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_familia AS STRING))
            ELSE NULL 
        END AS sk_familia,
        
        CASE 
            WHEN id_linha IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_linha AS STRING))
            ELSE NULL 
        END AS sk_linha,
        
        CASE 
            WHEN id_origem IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_origem AS STRING))
            ELSE NULL 
        END AS sk_origem,
        
        CASE 
            WHEN id_embalagem IS NOT NULL THEN CONCAT(empresa, '_', CAST(id_embalagem AS STRING))
            ELSE NULL 
        END AS sk_embalagem,

        -- Identificadores do Item
        CAST(id_item AS STRING) AS id_item,
        TRIM(UPPER(COALESCE(item_descricao, 'NÃO INFORMADO'))) AS descricao_item,


        -- Medidas e Pesos
        COALESCE(TRY_CAST(item_peso_unit AS DECIMAL(17, 2)), 0) AS peso_unitario_item,
        TRIM(UPPER(COALESCE(unidade_medida, 'NI'))) AS unidade_medida,


        -- Status e Flags (Convertidos para BOOLEAN)
        TRIM(UPPER(COALESCE(item_situacao, 'INATIVO'))) AS status_item,
        (compra_fabricacao = '1') AS is_fabricacao, -- True se for fabricação, False se for compra
        (comercializavel = '1') AS is_comercializavel,
        CASE WHEN subproduto = 1 THEN TRUE ELSE FALSE END AS is_subproduto,

        -- Datas
        TRY_CAST(data_cadastro AS DATE) AS data_cadastro,
        TRY_CAST(data_alteracao AS DATE) AS data_alteracao,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa para o mesmo item
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_item -- Agrupa pela nossa chave única
            ORDER BY
                data_alteracao DESC NULLS LAST, -- Prioriza o registro com a alteração mais recente
                data_cadastro DESC NULLS LAST
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1