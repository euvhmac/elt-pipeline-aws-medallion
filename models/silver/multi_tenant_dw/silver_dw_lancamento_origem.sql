{{
    config(
        materialized='incremental',
        unique_key='sk_lancamento',
        incremental_strategy='merge',
        tags=['silver', 'dw_lancamento_origem']
    )
}}


-- Uniao de todos os tenants via macro parametrica
WITH unioned_sources AS (
    {{ union_sources('dw_lancamento_origem') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key)
        CONCAT(
            empresa, '_',
            CAST(COALESCE(ano, 0) AS STRING), '_',
            CAST(COALESCE(mes, 0) AS STRING), '_',
            CAST(COALESCE(lancamento_numero, '') AS STRING), '_',
            CAST(COALESCE(id_empresa, 0) AS STRING), '_',
            CAST(COALESCE(id_analitico, '') AS STRING)
        ) AS sk_lancamento,
        
        -- Chaves Estrangeiras (Surrogate Keys) para relacionamento
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_item, 0), -1) AS STRING)) AS sk_item,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_danfe_numint, 0), -1) AS STRING)) AS sk_danfe,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_clifor_lancamento, 0), -1) AS STRING)) AS sk_cliente_fornecedor,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_filial, 0), -1) AS STRING)) AS sk_filial,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_unidade, 0), -1) AS STRING)) AS sk_unidade,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_conta, 0), -1) AS STRING)) AS sk_conta_contabil,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_centro_custo, 0), -1) AS STRING)) AS sk_centro_custo,
        CONCAT(empresa, '_', CAST(COALESCE(NULLIF(id_projeto, 0), -1) AS STRING)) AS sk_projeto,

        -- Identificadores Originais (todos mantidos)
        CAST(id_empresa AS STRING) AS id_empresa,
        CAST(ano AS INT) AS ano,
        CAST(mes AS INT) AS mes,
        CAST(id_filial AS STRING) AS id_filial,
        CAST(id_unidade AS STRING) AS id_unidade,
        CAST(id_conta AS STRING) AS id_conta,
        CAST(id_centro_custo AS STRING) AS id_centro_custo,
        CAST(id_item AS STRING) AS id_item,
        CAST(id_clifor_lancamento AS STRING) AS id_clifor_lancamento,
        CAST(id_equipamento AS STRING) AS id_equipamento,
        CAST(id_projeto AS STRING) AS id_projeto,
        CAST(lancamento_numero AS STRING) AS lancamento_numero,
        CAST(id_analitico AS STRING) AS id_analitico,
        CAST(id_danfe_numint AS STRING) AS id_danfe_numint,
        CAST(numero_sequencial_entrada AS STRING) AS numero_sequencial_entrada,
        CAST(id_ordem_servico AS STRING) AS id_ordem_servico,
        
        -- Datas e Timestamps
        TRY_CAST(`data` AS DATE) AS data_lancamento,
        TRY_CAST(data_criacao AS DATE) AS data_criacao,
        TRY_TO_TIMESTAMP(
            CONCAT(
                NULLIF(TRIM(data_entrada_sistema), ''),
                ' ',
                NULLIF(TRIM(hora_entrada_sistema), '')
            ),
            'yyyy-MM-dd HH:mm:ss'
        ) AS timestamp_entrada_sistema,
        
        -- Fatos e Métricas (Valores)
        COALESCE(TRY_CAST(peso AS DECIMAL(18, 4)), 0) AS peso,
        COALESCE(TRY_CAST(quantidade AS DECIMAL(18, 4)), 0) AS quantidade,
        COALESCE(TRY_CAST(valor_unitario AS DECIMAL(18, 4)), 0) AS valor_unitario,
        COALESCE(TRY_CAST(valor AS DECIMAL(18, 2)), 0) AS valor,
        
        -- Atributos Descritivos (todos mantidos)
        TRIM(UPPER(COALESCE(cpf, ''))) AS cpf,
        TRIM(UPPER(COALESCE(sigla, ''))) AS sigla,
        TRIM(UPPER(COALESCE(documento, ''))) AS documento,
        TRIM(UPPER(COALESCE(documento_vinculado, ''))) AS documento_vinculado,
        TRIM(UPPER(COALESCE(observacao_pagamento_recebimento, ''))) AS observacao_pagamento_recebimento,
        TRIM(UPPER(COALESCE(tipo, 'NÃO INFORMADO'))) AS tipo_lancamento,
        TRIM(UPPER(COALESCE(descricao_equipamento, ''))) AS descricao_equipamento,
        TRIM(UPPER(COALESCE(descricao_projeto, ''))) AS descricao_projeto,
        TRIM(UPPER(COALESCE(placa, ''))) AS placa,
        TRIM(UPPER(COALESCE(lote_numero, ''))) AS lote_numero,
        TRIM(UPPER(COALESCE(transacao, ''))) AS transacao,
        TRIM(UPPER(COALESCE(usuario, ''))) AS usuario,
        TRIM(UPPER(COALESCE(descricao_adicional, ''))) AS descricao_adicional,
        TRIM(UPPER(COALESCE(informacao_uso_compra, ''))) AS informacao_uso_compra,
        TRIM(UPPER(COALESCE(informacao_complementar_compra, ''))) AS informacao_complementar_compra,
        TRIM(UPPER(COALESCE(informacao_baixa_estoque, ''))) AS informacao_baixa_estoque,
        
        -- Metadados
        empresa

    FROM unioned_sources
    {%- if is_incremental() %}
    WHERE data_criacao > (SELECT MAX(data_criacao) FROM {{ this }})
    {%- endif %}
),

-- Remove duplicatas baseadas na chave única
deduplicated AS (
    SELECT
        sk_lancamento,
        sk_item,
        sk_danfe,
        sk_cliente_fornecedor,
        sk_filial,
        sk_unidade,
        sk_conta_contabil,
        sk_centro_custo,
        sk_projeto,
        id_empresa,
        ano,
        mes,
        id_filial,
        id_unidade,
        id_conta,
        id_centro_custo,
        id_item,
        id_clifor_lancamento,
        id_equipamento,
        id_projeto,
        lancamento_numero,
        id_analitico,
        id_danfe_numint,
        numero_sequencial_entrada,
        id_ordem_servico,
        data_lancamento,
        data_criacao,
        timestamp_entrada_sistema,
        peso,
        quantidade,
        valor_unitario,
        valor,
        cpf,
        sigla,
        documento,
        documento_vinculado,
        observacao_pagamento_recebimento,
        tipo_lancamento,
        descricao_equipamento,
        descricao_projeto,
        placa,
        lote_numero,
        transacao,
        usuario,
        descricao_adicional,
        informacao_uso_compra,
        informacao_complementar_compra,
        informacao_baixa_estoque,
        empresa,
        ROW_NUMBER() OVER (
            PARTITION BY sk_lancamento
            ORDER BY timestamp_entrada_sistema DESC NULLS LAST, data_lancamento DESC
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados sem duplicatas
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1
