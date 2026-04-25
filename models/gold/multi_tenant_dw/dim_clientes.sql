-- depends_on: {{ ref('silver_dw_clientes') }}
-- depends_on: {{ ref('silver_dw_cidade') }}
-- depends_on: {{ ref('silver_dw_rota') }}
-- depends_on: {{ ref('silver_dw_ramo') }}
-- depends_on: {{ ref('silver_dw_rede') }}
-- depends_on: {{ ref('silver_dw_vendedor') }}
-- depends_on: {{ ref('silver_dw_tipocliente') }}

{{ config(materialized='table') }}

-- CTE para selecionar a tabela fato principal de clientes
WITH stg_clientes AS (
    SELECT * FROM {{ ref('silver_dw_clientes') }}
),

-- CTEs para selecionar as tabelas de dimensão
stg_cidades AS (
    SELECT * FROM {{ ref('silver_dw_cidade') }}
),

stg_rotas AS (
    SELECT * FROM {{ ref('silver_dw_rota') }}
),

stg_ramos AS (
    SELECT * FROM {{ ref('silver_dw_ramo') }}
),

stg_redes AS (
    SELECT * FROM {{ ref('silver_dw_rede') }}
),

stg_vendedores AS (
    SELECT * FROM {{ ref('silver_dw_vendedor') }}
),

stg_tipos_cliente AS (
    SELECT * FROM {{ ref('silver_dw_tipocliente') }}
),

-- Realiza o JOIN de todas as tabelas Silver para criar o modelo denormalizado
final_join AS (
    SELECT
        -- Chave principal da tabela Gold
        clientes.sk_cliente,
        clientes.id_cliente,
        
        -- Informações do Cliente
        clientes.nome_fantasia,
        clientes.razao_social,
        COALESCE(
            NULLIF(TRIM(clientes.cnpj), ''),
            NULLIF(TRIM(clientes.cpf), '')
        ) AS cpf_cnpj,
        tipos_cliente.descricao AS tipo_cliente,
        clientes.data_inicio_atividade,
        clientes.situacao_cliente,
        clientes.empresa,

        -- Informações de Localização
        cidades.nome_cidade,
        cidades.sigla_uf AS estado,

        -- Informações de Vendas e Rota
        rotas.descricao AS rota,
        vendedores.nome_vendedor,
        clientes.id_vendedor, -- Mantendo o ID original se necessário

        -- Informações Comerciais
        clientes.condicao_pagamento,
        clientes.codigo_lista_preco,
        clientes.tabela_preco,

        -- Classificações
        ramos.ramo_atividade,
        redes.id_rede,
        redes.nome_rede,

        -- Deduplicação por sk_cliente
        ROW_NUMBER() OVER (
            PARTITION BY clientes.sk_cliente
            ORDER BY clientes.id_cliente
        ) AS rn
        
    FROM stg_clientes AS clientes

    LEFT JOIN stg_cidades AS cidades
        ON clientes.id_cidade = cidades.id_cidade AND clientes.empresa = cidades.empresa

    LEFT JOIN stg_rotas AS rotas
        ON clientes.sk_rota = rotas.sk_rota

    LEFT JOIN stg_ramos AS ramos
        ON clientes.sk_ramo = ramos.sk_ramo

    LEFT JOIN stg_redes AS redes
        ON clientes.sk_rede = redes.sk_rede

    LEFT JOIN stg_vendedores AS vendedores
        ON clientes.sk_vendedor = vendedores.sk_vendedor

    LEFT JOIN stg_tipos_cliente AS tipos_cliente
        ON clientes.sk_tipo_cliente = tipos_cliente.sk_tipo_cliente
)

-- Seleção final para a tabela Gold com deduplicação
SELECT
    * EXCEPT (rn)
FROM final_join
WHERE rn = 1
ORDER BY empresa, id_cliente