-- depends_on: {{ ref('dim_produtos') }}
-- Dimensão de Produtos consolidada e simplificada para consumo final
WITH produtos_gold AS (
    SELECT 
        -- Identificadores
        id_item,
        sk_item,
        id_grupo,
        sk_grupo,
        id_familia,
        sk_familia,
        
        -- Descrições
        descricao_item,
        descricao_grupo,
        descricao_familia,
        descricao_linha,
        descricao_classe,
        descricao_tipo_item,
        descricao_marca,
        descricao_origem,
        descricao_area_geografica,
        
        -- Detalhes de Embalagem
        nome_embalagem,
        tipo_embalagem,
        peso_embalagem,
        
        -- Medidas e Unidades
        peso_unitario_item,
        unidade_medida,
        
        -- Status e Flags
        status_item,
        is_comercializavel,
        is_fabricacao,
        is_subproduto,
        
        -- Datas
        data_cadastro,
        data_alteracao,
        
        -- Metadados
        empresa
        
    FROM {{ ref('dim_produtos') }}
)

SELECT 
    -- Identificadores
       id_item,
        sk_item,
        id_grupo,
        sk_grupo,
        id_familia,
        sk_familia,
        
        -- Descrições
        descricao_item,
        descricao_grupo,
        descricao_familia,
    
    -- Metadados
    empresa
    
FROM produtos_gold
ORDER BY empresa, descricao_item
