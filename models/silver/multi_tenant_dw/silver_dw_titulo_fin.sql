{{
    config(
        materialized='incremental',
        unique_key='sk_titulo_financeiro',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}


WITH unioned_sources AS (
    {{ union_sources('dw_titulo_fin') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key) para o título
        CONCAT(
            empresa, '_', 
            COALESCE(CAST(num_pedido AS STRING), '-1'), '_',
            COALESCE(CAST(nosso_numero AS STRING), '-1'), '_',
            COALESCE(CAST(nosso_digito AS STRING), '-1'), '_',
            COALESCE(CAST(num_documento AS STRING), '-1'), '_',
            COALESCE(CAST(num_interno AS STRING), '-1')
        ) AS sk_titulo_financeiro,

        -- Chaves Estrangeiras para relacionamento com outras tabelas Silver
        CONCAT(empresa, '_', CAST(id_cliente AS STRING)) AS sk_cliente,
        CONCAT(empresa, '_', CAST(id_vendedor AS STRING)) AS sk_vendedor,
        CONCAT(empresa, '_', CAST(id_condicao_pagto AS STRING)) AS sk_condicao_pagamento,

        -- Identificadores e Chaves (padronizados como STRING)
        CAST(id_empresa AS STRING) AS id_empresa,
        CAST(id_filial AS STRING) AS id_filial,
        CAST(num_documento AS STRING) AS num_documento,
        CAST(parcela AS STRING) AS parcela,
        CAST(id_portador AS STRING) AS id_portador,

        -- Datas
        TRY_CAST(data_emissao AS DATE) AS data_emissao,
        TRY_CAST(data_vencimento AS DATE) AS data_vencimento,
        TRY_CAST(data_pagamento AS DATE) AS data_pagamento,
        TRY_CAST(data_vencto_original AS DATE) AS data_vencimento_original,
        TRY_CAST(data_credito AS DATE) AS data_credito,
        
        -- Valores Monetários (tratados com COALESCE para evitar nulos)
        COALESCE(TRY_CAST(valor_titulo AS DECIMAL(17, 2)), 0) AS valor_titulo,
        COALESCE(TRY_CAST(valor_pagamento AS DECIMAL(17, 2)), 0) AS valor_pago,
        COALESCE(TRY_CAST(valor_saldo_devedor AS DECIMAL(17, 2)), 0) AS valor_saldo_devedor,
        COALESCE(TRY_CAST(valor_juro_pagto AS DECIMAL(17, 2)), 0) AS valor_juros,
        COALESCE(TRY_CAST(valor_multa AS DECIMAL(17, 2)), 0) AS valor_multa,
        COALESCE(TRY_CAST(valor_desconto_pagto AS DECIMAL(17, 2)), 0) AS valor_desconto,

        -- Status e Descrições (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(status_tit, 'NÃO INFORMADO'))) AS status_titulo,
        TRIM(UPPER(COALESCE(tipo_documento, 'NÃO INFORMADO'))) AS tipo_documento,
        TRIM(UPPER(COALESCE(nome_portador, 'NÃO INFORMADO'))) AS nome_portador,
        TRIM(UPPER(COALESCE(nome_cliente, ''))) AS nome_cliente,
        
        -- Metadados
        empresa,
        -- Assumindo que data_criacao ou data_movimento pode ser usada para desempate.
        -- Se houver um campo de data de alteração, ele seria ideal aqui.
        TRY_CAST(data_movimento AS TIMESTAMP) AS data_movimento

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa para a mesma chave de título
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_titulo_financeiro -- Agrupa por nossa chave única do título
            ORDER BY
                data_movimento DESC NULLS LAST, -- Prioriza o registro com o movimento mais recente
                data_emissao DESC NULLS LAST
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados desduplicados
-- O DBT com merge strategy já cuida de comparar com dados existentes via unique_key
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1