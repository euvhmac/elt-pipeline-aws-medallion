-- depends_on: {{ ref('silver_dw_item') }}
-- depends_on: {{ ref('silver_dw_classe') }}
-- depends_on: {{ ref('silver_dw_embalagem') }}
-- depends_on: {{ ref('silver_dw_familia') }}
-- depends_on: {{ ref('silver_dw_grupo') }}
-- depends_on: {{ ref('silver_dw_linha') }}
-- depends_on: {{ ref('silver_dw_tipoitem') }}
-- depends_on: {{ ref('silver_dw_origem') }}
-- depends_on: {{ ref('silver_dw_marca_item') }}
-- depends_on: {{ ref('silver_dw_areageo') }}

{{ config(materialized='table') }}

-- CTE para a tabela fato principal de itens
WITH stg_itens AS (
    SELECT * FROM {{ ref('silver_dw_item') }}
),

-- CTEs para todas as dimensões de suporte
stg_classes AS (
    SELECT sk_classe, descricao_classe FROM {{ ref('silver_dw_classe') }}
),
stg_embalagens AS (
    SELECT sk_embalagem, nome_embalagem, tipo_embalagem, peso_embalagem FROM {{ ref('silver_dw_embalagem') }}
),
stg_familias AS (
    SELECT sk_familia, id_familia, descricao_familia FROM {{ ref('silver_dw_familia') }}
),
stg_grupos AS (
    SELECT sk_grupo, id_grupo, descricao_grupo FROM {{ ref('silver_dw_grupo') }}
),
stg_linhas AS (
    SELECT sk_linha, descricao_linha FROM {{ ref('silver_dw_linha') }}
),
stg_tipos_item AS (
    SELECT sk_tipo_item, descricao_tipo_item FROM {{ ref('silver_dw_tipoitem') }}
),
stg_origens AS (
    SELECT sk_origem, descricao_origem FROM {{ ref('silver_dw_origem') }}
),
stg_marcas AS (
    SELECT sk_marca_item, descricao_marca FROM {{ ref('silver_dw_marca_item') }}
),
stg_areas_geo AS (
    SELECT sk_area_geografica, descricao_area_geografica FROM {{ ref('silver_dw_areageo') }}
),

-- Realiza o JOIN de todas as tabelas para criar a visão 360º do produto
final AS (
    SELECT 
        -- Chave principal da dimensão
        itens.sk_item,
        itens.id_item,
        grupos.id_grupo,
        grupos.sk_grupo,
        familias.id_familia,
        familias.sk_familia,

        -- Descrições e Nomes
        itens.descricao_item,
        grupos.descricao_grupo,
        familias.descricao_familia,

        -- Hierarquia e Classificação do Produto (campos das dimensões)
        linhas.descricao_linha,
        classes.descricao_classe,
        tipos_item.descricao_tipo_item,
        marcas.descricao_marca,
        origens.descricao_origem,
        areas_geo.descricao_area_geografica,

        -- Detalhes de Embalagem (da dimensão de embalagem)
        embalagens.nome_embalagem,
        embalagens.tipo_embalagem,
        embalagens.peso_embalagem,
        
        -- Medidas e Unidades
        itens.peso_unitario_item,
        itens.unidade_medida,

        -- Status e Flags
        itens.status_item,
        itens.is_comercializavel,
        itens.is_fabricacao,
        itens.is_subproduto,

        -- Outros Atributos
        itens.data_cadastro,
        itens.data_alteracao,
        itens.empresa,

        -- Deduplicação
        ROW_NUMBER() OVER (
            PARTITION BY itens.sk_item
            ORDER BY LENGTH(itens.descricao_item) DESC, itens.descricao_item DESC
        ) AS rn

    FROM stg_itens AS itens

    LEFT JOIN stg_grupos AS grupos ON itens.sk_grupo = grupos.sk_grupo
    LEFT JOIN stg_classes AS classes ON itens.sk_classe = classes.sk_classe
    LEFT JOIN stg_embalagens AS embalagens ON itens.sk_embalagem = embalagens.sk_embalagem
    LEFT JOIN stg_familias AS familias ON itens.sk_familia = familias.sk_familia
    LEFT JOIN stg_linhas AS linhas ON itens.sk_linha = linhas.sk_linha
    LEFT JOIN stg_tipos_item AS tipos_item ON itens.sk_tipo_item = tipos_item.sk_tipo_item
    LEFT JOIN stg_origens AS origens ON itens.sk_origem = origens.sk_origem
    LEFT JOIN stg_marcas AS marcas ON itens.sk_marca_item = marcas.sk_marca_item
    LEFT JOIN stg_areas_geo AS areas_geo ON itens.sk_area_geografica = areas_geo.sk_area_geografica
)

-- Seleção final para a tabela Gold com deduplicação
SELECT
    * EXCEPT (rn)
FROM final
WHERE rn = 1
ORDER BY empresa, descricao_item