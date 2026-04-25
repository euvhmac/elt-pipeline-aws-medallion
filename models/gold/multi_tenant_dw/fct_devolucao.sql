-- depends_on: {{ ref('silver_dw_devolucao') }}
-- depends_on: {{ ref('silver_dw_item') }}
-- depends_on: {{ ref('silver_dw_clientes') }}
-- depends_on: {{ ref('silver_dw_vendedor') }}
-- depends_on: {{ ref('silver_dw_cidade') }}

{{ config(materialized='table') }}

-- CTE para a tabela fato principal de devoluções
WITH stg_devolucoes AS (
    SELECT * FROM {{ ref('silver_dw_devolucao') }}
),

-- CTEs para as dimensões que serão unidas
stg_produtos AS (
    SELECT sk_item, descricao_item FROM {{ ref('silver_dw_item') }}
),
stg_clientes AS (
    SELECT sk_cliente, razao_social FROM {{ ref('silver_dw_clientes') }}
),
stg_vendedores AS (
    SELECT sk_vendedor, nome_vendedor FROM {{ ref('silver_dw_vendedor') }}
),
stg_cidades AS (
    SELECT sk_cidade, nome_cidade FROM {{ ref('silver_dw_cidade') }}
),

-- Realiza o JOIN entre a fato e as dimensões para criar o modelo denormalizado
final AS (
    SELECT 
        -- Chave Primária
        devolucoes.sk_devolucao_item,

        -- Documentos
        devolucoes.numero_danfe_devolucao,
        devolucoes.serie_danfe_devolucao,
        devolucoes.numero_danfe_origem,
        devolucoes.serie_danfe_origem,

        -- Dimensão de Tempo
        devolucoes.data_devolucao,
        YEAR(devolucoes.data_devolucao) AS ano_devolucao,
        MONTH(devolucoes.data_devolucao) AS mes_devolucao,
        QUARTER(devolucoes.data_devolucao) AS trimestre_devolucao,

        -- Dimensão de Produto (da gold_produtos)
        produtos.descricao_item,

        -- Dimensão de Cliente
        clientes.razao_social AS cliente_razao_social,

        -- Dimensão de Vendedor
        vendedores.nome_vendedor,

        -- Dimensão Geográfica
        cidades.nome_cidade,

        -- Fatos e Métricas (Quantidades e Valores)
        devolucoes.quantidade_devolvida,
        devolucoes.valor_total_item AS valor_devolvido,
        devolucoes.peso_liquido_devolvido,

        -- Atributos Descritivos da Devolução
        -- CORREÇÃO APLICADA: Divisão da coluna 'motivo_devolucao'
        CASE 
            WHEN INSTR(devolucoes.motivo_devolucao, ' - ') > 0
            THEN TRIM(SPLIT(devolucoes.motivo_devolucao, ' - ')[0])
            ELSE 'GERAL'
        END AS setor_devolucao,

        CASE 
            WHEN INSTR(devolucoes.motivo_devolucao, ' - ') > 0
            THEN TRIM(SPLIT(devolucoes.motivo_devolucao, ' - ')[1])
            ELSE devolucoes.motivo_devolucao
        END AS motivo_especifico,

        devolucoes.tipo_devolucao,
        devolucoes.empresa

    FROM stg_devolucoes AS devolucoes

    LEFT JOIN stg_produtos AS produtos
        ON devolucoes.sk_item = produtos.sk_item

    LEFT JOIN stg_clientes AS clientes
        ON devolucoes.sk_cliente = clientes.sk_cliente

    LEFT JOIN stg_vendedores AS vendedores
        ON devolucoes.sk_vendedor = vendedores.sk_vendedor
    
    LEFT JOIN stg_cidades AS cidades
        ON devolucoes.sk_cidade = cidades.sk_cidade
),

-- Remove duplicatas que podem surgir dos JOINs
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_devolucao_item
            ORDER BY data_devolucao DESC
        ) AS rn
    FROM final
)

-- Seleção final para a tabela Gold
SELECT * EXCEPT (rn) FROM deduplicated
WHERE rn = 1
ORDER BY empresa, data_devolucao