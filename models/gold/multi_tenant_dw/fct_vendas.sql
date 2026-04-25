-- depends_on: {{ ref('silver_dw_vendas') }}
-- depends_on: {{ ref('silver_dw_item') }}
-- depends_on: {{ ref('silver_dw_clientes') }}
-- depends_on: {{ ref('silver_dw_vendedor') }}
-- depends_on: {{ ref('silver_dw_cidade') }}
-- depends_on: {{ ref('silver_dw_rota') }}
-- depends_on: {{ ref('silver_dw_rede') }}

{{ config(
    unique_key='sk_venda_item',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

-- CTE para a tabela fato principal de vendas (agora com 5 empresas)
WITH stg_vendas AS (
    SELECT * FROM {{ ref('silver_dw_vendas') }}
),

-- CTEs para as dimensões que serão unidas (assumindo que também contêm as 5 empresas)
stg_produtos AS (
    SELECT 
        sk_item, 
        descricao_item
    FROM {{ ref('silver_dw_item') }}
),
stg_clientes AS (
    SELECT 
        sk_cliente,
        razao_social
    FROM {{ ref('silver_dw_clientes') }}
),
stg_vendedores AS (
    SELECT 
        sk_vendedor, 
        nome_vendedor 
    FROM {{ ref('silver_dw_vendedor') }}
),
stg_cidades AS (
    SELECT 
        sk_cidade, 
        nome_cidade
    FROM {{ ref('silver_dw_cidade') }}
),
stg_rotas AS (
    SELECT 
        sk_rota, 
        descricao
    FROM {{ ref('silver_dw_rota') }}
),
stg_redes AS (
    SELECT
        sk_rede,
        nome_rede
    FROM {{ ref('silver_dw_rede') }}
),

-- Realiza o JOIN entre a fato e as dimensões e cria métricas de negócio
final AS (
    SELECT 
        -- Chave Primária e IDs de Negócio
        vendas.sk_venda_item,
        vendas.id_pedido,
        vendas.id_item_sequencia,

        -- Dimensão de Tempo
        vendas.data_emissao_pedido,
        vendas.data_entrega_pedido,
        YEAR(vendas.data_emissao_pedido) AS ano_pedido,
        MONTH(vendas.data_emissao_pedido) AS mes_pedido,
        QUARTER(vendas.data_emissao_pedido) AS trimestre_pedido,
        DATE_DIFF(vendas.data_entrega_pedido, vendas.data_emissao_pedido) AS prazo_entrega_dias,

        -- Dimensão de Produto
        produtos.descricao_item,

        -- Dimensão de Cliente
        clientes.razao_social AS cliente_razao_social,

        -- Dimensão de Vendedor e Hierarquia
        vendedores.nome_vendedor,

        -- Dimensão Geográfica
        cidades.nome_cidade AS cliente_cidade,
        rotas.descricao,

        -- Dimensão de Rede
        redes.nome_rede,

        -- Fatos e Métricas (Quantidades)
        vendas.quantidade_pedido,
        vendas.quantidade_bonificada,
        vendas.peso_pedido,
        vendas.peso_atendido,

        -- Fatos e Métricas (Valores Monetários)
        vendas.preco_base,
        vendas.valor_total_item,
        vendas.valor_desconto_item,
        vendas.valor_desconto_cliente,
        (vendas.valor_desconto_item + vendas.valor_desconto_cliente) AS valor_desconto_total,
        (vendas.valor_total_item - (vendas.valor_desconto_item + vendas.valor_desconto_cliente)) AS valor_liquido_item,
        vendas.valor_despesas_acessorias,
        
        -- Atributos da Venda
        vendas.status_pedido,
        vendas.is_bonificacao,
        vendas.is_faturado,
        vendas.prazo_medio_recebimento,
        vendas.id_cfop,
        vendas.cfop_nome,

        -- Flags de Bloqueio
        vendas.is_bloqueio_comercial,
        vendas.is_bloqueio_financeiro,

        -- Metadados
        vendas.empresa -- tenant column: Unit_01 through Unit_05

    FROM stg_vendas AS vendas

    LEFT JOIN stg_produtos AS produtos
        ON vendas.sk_item = produtos.sk_item

    LEFT JOIN stg_clientes AS clientes
        ON vendas.sk_cliente = clientes.sk_cliente

    LEFT JOIN stg_vendedores AS vendedores
        ON vendas.sk_vendedor = vendedores.sk_vendedor
    
    LEFT JOIN stg_cidades AS cidades
        ON vendas.sk_cidade = cidades.sk_cidade

    LEFT JOIN stg_rotas AS rotas
        ON vendas.sk_rota = rotas.sk_rota

    LEFT JOIN stg_redes AS redes
        ON vendas.sk_rede = redes.sk_rede
    
    -- Filtro de negócio pode ser ajustado conforme necessário
    WHERE vendas.status_pedido NOT IN ('CANCELADO', 'BLOQUEADO', 'PENDENTE')
    
    {% if is_incremental() %}
    -- Filtra apenas vendas novas ou atualizadas
    AND vendas.data_emissao_pedido >= (
        SELECT COALESCE(DATE_SUB(MAX(data_emissao_pedido), 7), '2000-01-01')
        FROM {{ this }}
    )
    {% endif %}
),

-- Remove duplicatas que podem surgir dos JOINs
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_venda_item
            ORDER BY data_emissao_pedido DESC
        ) AS rn
    FROM final
)

-- Seleção final para a tabela Gold
SELECT * EXCEPT (rn) FROM deduplicated
WHERE rn = 1
ORDER BY empresa, data_emissao_pedido