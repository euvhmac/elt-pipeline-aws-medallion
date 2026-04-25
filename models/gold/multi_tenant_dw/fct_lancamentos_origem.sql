-- depends_on: {{ ref('silver_dw_lancamento_origem') }}
-- depends_on: {{ ref('dim_contas_contabeis') }}
-- depends_on: {{ ref('dim_centros_custos') }}
-- depends_on: {{ ref('dim_produtos') }}
-- depends_on: {{ ref('silver_dw_filial') }}

{{ config(
    unique_key='sk_lancamento',
    incremental_strategy='merge',
    on_schema_change='append_new_columns'
) }}

-- CTE para a tabela fato principal de lançamentos
WITH stg_lancamentos AS (
    SELECT * FROM {{ ref('silver_dw_lancamento_origem') }}
    {% if is_incremental() %}
    WHERE data_lancamento > (SELECT MAX(data_lancamento) FROM {{ this }})
       OR timestamp_entrada_sistema > (SELECT MAX(timestamp_entrada_sistema) FROM {{ this }})
    {% endif %}
),

-- CTEs para as dimensões que serão unidas
stg_contas AS (
    SELECT sk_conta_contabil, descricao_conta, grupo_conta, natureza_conta, tipo_conta FROM {{ ref('dim_contas_contabeis') }}
),
stg_ccusto AS (
    SELECT sk_centro_custo, descricao_centro_custo, tipo AS tipo_centro_custo FROM {{ ref('dim_centros_custos') }}
),
stg_produtos AS (
    SELECT sk_item, descricao_item FROM {{ ref('dim_produtos') }}
),
stg_filiais AS (
    SELECT sk_filial, nome_filial FROM {{ ref('silver_dw_filial') }}
),

-- Realiza o JOIN entre a fato e as dimensões para criar o modelo denormalizado
final AS (
    SELECT 
        -- Colunas da Silver (Fato), com exclusões aplicadas
        lanc.sk_lancamento,
        lanc.sk_item,
        lanc.sk_danfe,
        lanc.sk_cliente_fornecedor,
        lanc.sk_filial,
        lanc.sk_unidade,
        lanc.sk_conta_contabil,
        lanc.sk_centro_custo,
        lanc.sk_projeto,
        lanc.id_empresa,
        lanc.id_filial,
        lanc.id_unidade,
        lanc.id_conta,
        lanc.id_centro_custo,
        lanc.id_item,
        lanc.id_clifor_lancamento,
        -- id_equipamento EXCLUÍDO
        lanc.id_projeto,
        lanc.lancamento_numero,
        -- id_analitico EXCLUÍDO
        lanc.id_danfe_numint,
        lanc.numero_sequencial_entrada,
        lanc.id_ordem_servico,
        lanc.data_lancamento,
        lanc.data_criacao,
        lanc.timestamp_entrada_sistema,
        lanc.peso,
        lanc.quantidade,
        lanc.valor_unitario,
        lanc.valor,
        lanc.cpf,
        lanc.sigla,
        lanc.documento,
        lanc.documento_vinculado,
        lanc.observacao_pagamento_recebimento,
        lanc.tipo_lancamento,
        -- descricao_equipamento EXCLUÍDO
        lanc.descricao_projeto,
        lanc.placa,
        lanc.lote_numero,
        lanc.transacao,
        lanc.usuario,
        lanc.descricao_adicional,
        lanc.informacao_uso_compra,
        lanc.informacao_complementar_compra,
        lanc.informacao_baixa_estoque,
        lanc.empresa,

        -- Colunas Enriquecidas (Dimensões)
        contas.descricao_conta,
        contas.grupo_conta,
        contas.natureza_conta,
        contas.tipo_conta,
        ccusto.descricao_centro_custo,
        ccusto.tipo_centro_custo,
        filiais.nome_filial,
        produtos.descricao_item,
        
        -- Métricas Calculadas
        YEAR(lanc.data_lancamento) AS ano_lancamento,
        MONTH(lanc.data_lancamento) AS mes_lancamento,
        CASE
            WHEN UPPER(lanc.tipo_lancamento) = 'D' THEN lanc.valor
            WHEN UPPER(lanc.tipo_lancamento) = 'C' THEN -lanc.valor
            ELSE 0
        END AS valor_liquido

    FROM stg_lancamentos AS lanc

    LEFT JOIN stg_contas AS contas
        ON lanc.sk_conta_contabil = contas.sk_conta_contabil

    LEFT JOIN stg_ccusto AS ccusto
        ON lanc.sk_centro_custo = ccusto.sk_centro_custo
        
    LEFT JOIN stg_produtos AS produtos
        ON lanc.sk_item = produtos.sk_item

    LEFT JOIN stg_filiais AS filiais
        ON lanc.sk_filial = filiais.sk_filial

)

-- Seleção final para a tabela Gold
SELECT * FROM final
ORDER BY empresa, data_lancamento