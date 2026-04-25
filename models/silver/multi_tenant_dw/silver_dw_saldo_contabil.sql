{{
    config(
        materialized='incremental',
        unique_key='sk_saldo_contabil',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}


-- CTEs para carregar os dados de saldos contábeis de cada empresa
WITH unioned_sources AS (
    {{ union_sources('dw_saldo_contabil') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key) do saldo mensal da conta
        CONCAT(
            empresa, '_',
            CAST(COALESCE(NULLIF(id_conta, 0), -1) AS STRING), '_',
            CAST(COALESCE(NULLIF(id_conta_superior, 0), -1) AS STRING), '_',
            CAST(COALESCE(NULLIF(id_empresa, 0), -1) AS STRING), '_',
            CAST(COALESCE(NULLIF(id_filial, 0), -1) AS STRING), '_',
            CAST(COALESCE(NULLIF(id_unidade, 0), -1) AS STRING), '_',
            CAST(COALESCE(NULLIF(ano, 0), -1) AS STRING), '_',
            LPAD(CAST(COALESCE(NULLIF(mes, 0), -1) AS STRING), 2, '0')
        ) AS sk_saldo_contabil,

        -- Chaves Estrangeiras (Surrogate Keys)
        CONCAT(empresa, '_', CAST(id_conta AS STRING)) AS sk_conta_contabil,
        -- Adicionar outras SKs se necessário (ex: sk_filial, sk_unidade)

        -- Dimensão de Tempo
        make_date(TRY_CAST(ano AS INT), TRY_CAST(mes AS INT), 1) AS data_saldo,
        CAST(ano AS INT) AS ano_saldo,
        CAST(mes AS INT) AS mes_saldo,

        -- Identificadores
        CAST(id_empresa AS STRING) AS id_empresa,
        CAST(id_filial AS STRING) AS id_filial,
        CAST(id_unidade AS STRING) AS id_unidade,
        CAST(id_analitico AS STRING) AS id_analitico,
        CAST(id_conta AS STRING) AS id_conta,
        CAST(id_conta_superior AS STRING) AS id_conta_superior,
        CAST(ano AS INT) AS ano,
        CAST(mes AS INT) AS mes,
        
        -- Fatos e Métricas (Valores)
        COALESCE(TRY_CAST(valor_inicial AS DECIMAL(17, 2)), 0) AS valor_saldo_inicial,
        COALESCE(TRY_CAST(valor_debito AS DECIMAL(17, 2)), 0) AS valor_debito_mes,
        COALESCE(TRY_CAST(valor_credito AS DECIMAL(17, 2)), 0) AS valor_credito_mes,
        COALESCE(TRY_CAST(valor_final AS DECIMAL(17, 2)), 0) AS valor_saldo_final,
        
        -- Atributos Descritivos do Saldo
        TRIM(UPPER(COALESCE(tipo_saldo_inicial, ''))) AS tipo_saldo_inicial, -- 'D' ou 'C'
        TRIM(UPPER(COALESCE(tipo_saldo_final, ''))) AS tipo_saldo_final, -- 'D' ou 'C'
        
        -- Metadados
        empresa,
        TRY_CAST(data_criacao AS TIMESTAMP) AS data_criacao

    FROM unioned_sources
),

-- Remove duplicatas
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_saldo_contabil -- Agrupa pela nossa chave única
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
    -- Filtra apenas registros novos ou atualizados
    AND data_criacao > (SELECT MAX(data_criacao) FROM {{ this }})
{% endif %}