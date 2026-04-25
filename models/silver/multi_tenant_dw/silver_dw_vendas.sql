{{
    config(
        materialized='incremental',
        unique_key='sk_venda_item',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}


WITH unioned_sources AS (
    {{ union_sources('dw_vendas') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key) do item do pedido
        CONCAT(
            empresa, '_',
            COALESCE(CAST(id_pedido AS STRING), '-1'), '_',
            COALESCE(CAST(id_cliente AS STRING), '-1'), '_',
            COALESCE(CAST(id_vendedor AS STRING), '-1'), '_',
            COALESCE(CAST(id_item AS STRING), '-1'), '_',
            COALESCE(CAST(id_item_seq AS STRING), '-1')
        ) AS sk_venda_item,

        -- Chaves Estrangeiras (Surrogate Keys)
        CONCAT(empresa, '_', CAST(id_cliente AS STRING)) AS sk_cliente,
        CONCAT(empresa, '_', CAST(id_item AS STRING)) AS sk_item,
        CONCAT(empresa, '_', CAST(id_vendedor AS STRING)) AS sk_vendedor,
        CONCAT(empresa, '_', CAST(id_cidade AS STRING)) AS sk_cidade,
        CONCAT(empresa, '_', CAST(id_rota AS STRING)) AS sk_rota,
        CONCAT(empresa, '_', CAST(id_rede AS STRING)) AS sk_rede,
        CONCAT(empresa, '_', CAST(id_vendedor_sup AS STRING)) AS sk_vendedor_supervisor,

        -- Identificadores do Pedido
        CAST(id_pedido AS STRING) AS id_pedido,
        CAST(id_item_seq AS STRING) AS id_item_sequencia,
        CAST(id_empresa AS STRING) AS id_empresa,
        CAST(id_filial AS STRING) AS id_filial,
        CAST(id_unidade AS STRING) AS id_unidade,
        CAST(numero_pedido_origem AS STRING) AS id_pedido_origem,
        
        -- Datas Principais
        TRY_CAST(ped_emissao AS DATE) AS data_emissao_pedido,
        TRY_CAST(ped_entrega AS DATE) AS data_entrega_pedido,
        
        -- Fatos e Métricas (Valores)
        COALESCE(TRY_CAST(quantidade_pedido AS DECIMAL(17, 2)), 0) AS quantidade_pedido,
        COALESCE(TRY_CAST(quantidade_bonifica AS DECIMAL(17, 2)), 0) AS quantidade_bonificada,
        COALESCE(TRY_CAST(peso_pedido AS DECIMAL(17, 2)), 0) AS peso_pedido,
        COALESCE(TRY_CAST(peso_atendido AS DECIMAL(19, 4)), 0) AS peso_atendido,
        COALESCE(TRY_CAST(valor_total AS DECIMAL(17, 2)), 0) AS valor_total_item,
        COALESCE(TRY_CAST(valor_venda AS DECIMAL(17, 2)), 0) AS valor_venda_item,
        COALESCE(TRY_CAST(ped_desconto AS DECIMAL(17, 2)), 0) AS valor_desconto_item,
        COALESCE(TRY_CAST(desconto_cliente AS DECIMAL(17, 2)), 0) AS valor_desconto_cliente,
        COALESCE(TRY_CAST(valor_despesas_aces AS DECIMAL(17, 2)), 0) AS valor_despesas_acessorias,
        COALESCE(TRY_CAST(preco_base AS DECIMAL(19, 4)), 0) AS preco_base,
        COALESCE(TRY_CAST(preco_medio AS DECIMAL(19, 4)), 0) AS preco_medio,
        COALESCE(TRY_CAST(preco_tabela AS INT), 0) AS id_preco_tabela,
        COALESCE(TRY_CAST(preco_ocorrencia AS INT), 0) AS id_preco_ocorrencia,
        COALESCE(TRY_CAST(prazo_medio_receb AS DECIMAL(17, 2)), 0) AS prazo_medio_recebimento,
        
        -- Status e Flags (VARCHAR(1) e similares)
        CAST(cfop_nome AS STRING) AS cfop_nome,
        TRIM(UPPER(COALESCE(status_pedido, 'NÃO INFORMADO'))) AS status_pedido,
        (bonificacao = '1') AS is_bonificacao,
        (ja_faturado = '1') AS is_faturado,
        (bloqueio_comercial = '1') AS is_bloqueio_comercial,
        (bloqueio_financeiro = '1') AS is_bloqueio_financeiro,
        (bloqueio_fiscal = '1') AS is_bloqueio_fiscal,
        (bloqueio_receita = '1') AS is_bloqueio_receita,
        (bloqueio_logistica = '1') AS is_bloqueio_logistica,
        
        -- IDs de Classificação (para serem usados nos JOINs da Gold)
        CAST(id_condpag AS STRING) AS id_condicao_pagamento,
        CAST(id_cfop AS INT) AS id_cfop,
        CAST(codigo_safra AS INT) AS id_safra,
        CAST(tipo_operacao AS INT) AS id_tipo_operacao,
        -- Colunas com caracteres especiais precisam de crases
        TRY_CAST('id_item-status' AS INT) AS id_status_item, 

        -- Metadados
        empresa,
        TRY_CAST(data_criacao AS TIMESTAMP) AS data_criacao -- Usado para desempate

    FROM unioned_sources
),

-- Remove duplicatas de itens de pedido
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_venda_item -- Agrupa pela nossa chave única
            ORDER BY
                data_criacao DESC NULLS LAST -- Prioriza o registro com a criação mais recente
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1

{% if is_incremental() %}
    -- Filtra apenas registros novos ou atualizados nas últimas 7 dias
    AND data_criacao > (SELECT MAX(data_criacao) FROM {{ this }})
{% endif %}