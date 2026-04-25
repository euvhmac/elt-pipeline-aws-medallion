-- depends_on: {{ ref('silver_dw_titulo_fin') }}
-- depends_on: {{ ref('silver_dw_clientes') }}
-- depends_on: {{ ref('silver_dw_vendedor') }}

{{
    config(
        materialized='incremental',
        unique_key='sk_titulo_financeiro',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

-- CTE para a tabela fato principal de títulos
WITH stg_titulos AS (
    SELECT * FROM {{ ref('silver_dw_titulo_fin') }}
),

-- CTEs para as dimensões que serão unidas
stg_clientes AS (
    SELECT sk_cliente, nome_fantasia, razao_social, tipo_pessoa, sk_rede FROM {{ ref('silver_dw_clientes') }}
),

stg_vendedores AS (
    SELECT sk_vendedor, nome_vendedor FROM {{ ref('silver_dw_vendedor') }}
),
stg_condpag AS (
    SELECT sk_condicao_pagamento, descricao_condicao_pagamento FROM {{ ref('silver_dw_condpag') }}
),

-- Realiza o JOIN entre a fato e as dimensões para enriquecer os dados
joined_data AS (
    SELECT 
        -- Chave primária da tabela fato
        titulos.sk_titulo_financeiro,

        -- Chaves estrangeiras
        titulos.sk_cliente,
        titulos.sk_vendedor,
        titulos.sk_condicao_pagamento,

        -- Informações do Título (da fato)
        titulos.id_empresa,
        titulos.id_filial,
        titulos.num_documento,
        titulos.parcela,
        titulos.data_emissao,
        titulos.data_vencimento,
        titulos.data_pagamento,
        titulos.valor_titulo,
        titulos.valor_pago,
        titulos.valor_saldo_devedor,
        titulos.valor_juros,
        titulos.valor_multa,
        titulos.valor_desconto,
        titulos.status_titulo,
        titulos.tipo_documento,
        titulos.nome_portador,
        titulos.empresa

    FROM stg_titulos AS titulos
),

-- Aplica regras de negócio e cria campos calculados (enriquecimento)
enriched_data AS (
    SELECT
        *,
        
        -- Situação do Título
        CASE
            WHEN data_vencimento < CURRENT_DATE() AND valor_saldo_devedor > 0 THEN 'VENCIDO'
            WHEN data_vencimento >= CURRENT_DATE() AND valor_saldo_devedor > 0 THEN 'A VENCER'
            WHEN valor_saldo_devedor <= 0 THEN 'QUITADO'
            ELSE 'INDEFINIDO'
        END AS situacao_titulo,
       
        -- Dias em Atraso (para títulos vencidos e não pagos)
        CASE
            WHEN data_vencimento < CURRENT_DATE() AND valor_saldo_devedor > 0
            THEN DATE_DIFF(CURRENT_DATE(), data_vencimento)
            ELSE 0
        END AS dias_atraso,
       
        -- Faixa de Valor
        CASE
            WHEN valor_titulo <= 1000 THEN 'ATE 1K'
            WHEN valor_titulo <= 5000 THEN '1K A 5K'
            WHEN valor_titulo <= 10000 THEN '5K A 10K'
            WHEN valor_titulo <= 50000 THEN '10K A 50K'
            WHEN valor_titulo <= 100000 THEN '50K A 100K'
            WHEN valor_titulo <= 500000 THEN '100K A 500K'
            WHEN valor_titulo <= 1000000 THEN '500K A 1M'
            WHEN valor_titulo <= 5000000 THEN '1M A 5M'
            WHEN valor_titulo <= 10000000 THEN '5M A 10M'
            ELSE 'ACIMA DE 10M'
        END AS faixa_valor_titulo,
       
        -- Classificação Faixa de Valor
        CASE
            WHEN valor_titulo <= 1000 THEN 1
            WHEN valor_titulo <= 5000 THEN 2
            WHEN valor_titulo <= 10000 THEN 3
            WHEN valor_titulo <= 50000 THEN 4
            WHEN valor_titulo <= 100000 THEN 5
            WHEN valor_titulo <= 500000 THEN 6
            WHEN valor_titulo <= 1000000 THEN 7
            WHEN valor_titulo <= 5000000 THEN 8
            WHEN valor_titulo <= 10000000 THEN 9
            ELSE 10
        END AS classificacao_faixa_valor,

        -- Faixa de Atraso
        CASE
            WHEN data_vencimento < CURRENT_DATE() AND valor_saldo_devedor > 0 THEN
                CASE
                    WHEN DATE_DIFF(CURRENT_DATE(), data_vencimento) <= 30 THEN '1-30 DIAS'
                    WHEN DATE_DIFF(CURRENT_DATE(), data_vencimento) <= 60 THEN '31-60 DIAS'
                    WHEN DATE_DIFF(CURRENT_DATE(), data_vencimento) <= 90 THEN '61-90 DIAS'
                    ELSE 'ACIMA DE 90 DIAS'
                END
            ELSE 'EM DIA'
        END AS faixa_atraso,

        -- Classificação Faixa de Atraso
        CASE
            WHEN data_vencimento < CURRENT_DATE() AND valor_saldo_devedor > 0 THEN
                CASE
                    WHEN DATE_DIFF(CURRENT_DATE(), data_vencimento) <= 30 THEN 1
                    WHEN DATE_DIFF(CURRENT_DATE(), data_vencimento) <= 60 THEN 2
                    WHEN DATE_DIFF(CURRENT_DATE(), data_vencimento) <= 90 THEN 3
                    ELSE 4
                END
            ELSE 0
        END AS classificacao_faixa_atraso,
 
        -- Valor Líquido do Título
        (valor_titulo - valor_desconto + valor_juros + valor_multa) AS valor_liquido
 
    FROM joined_data
)

-- Seleção final para a tabela Gold enriquecida
SELECT 
    *
FROM enriched_data
ORDER BY empresa, data_emissao