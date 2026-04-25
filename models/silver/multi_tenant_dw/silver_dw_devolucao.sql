
{{ config(
    unique_key='sk_devolucao_item',
    incremental_strategy='merge'
) }}

WITH unioned_sources AS (
    {{ union_sources('dw_devolucao') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key) da linha da devolução - composta por empresa + danfe_numero + data + id_cliente + id_item + id_vendedor
        CONCAT(
            empresa, '_',
            COALESCE(CAST(danfe_numero AS STRING), '-1'), '_',
            COALESCE(CAST(`data` AS STRING), '-1'), '_',
            COALESCE(CAST(id_cliente AS STRING), '-1'), '_',
            COALESCE(CAST(id_item AS STRING), '-1'), '_',
            COALESCE(CAST(id_vendedor AS STRING), '-1')
        ) AS sk_devolucao_item,

        -- Chaves Estrangeiras (Surrogate Keys) para relacionamento
        CONCAT(empresa, '_', CAST(id_cliente AS STRING)) AS sk_cliente,
        CONCAT(empresa, '_', CAST(id_vendedor AS STRING)) AS sk_vendedor,
        CONCAT(empresa, '_', CAST(id_item AS STRING)) AS sk_item,
        CONCAT(empresa, '_', CAST(id_cidade AS STRING)) AS sk_cidade,

        -- Identificadores do Documento de Devolução
        CAST(danfe_numero AS STRING) AS numero_danfe_devolucao,
        CAST(id_cliente AS STRING) AS id_cliente,
        CAST(id_item AS STRING) AS id_item,
        CAST(id_vendedor AS STRING) AS id_vendedor,
        CAST(danfe_serie AS STRING) AS serie_danfe_devolucao,

        -- Identificadores do Documento de Venda Original
        CAST(danfe_numero_origem AS STRING) AS numero_danfe_origem,
        CAST(danfe_serie_origem AS STRING) AS serie_danfe_origem,
        
        -- Data da Devolução (coluna "data" precisa de aspas)
        TRY_CAST(`data` AS DATE) AS data_devolucao,

        -- Fatos e Métricas (Valores)
        COALESCE(TRY_CAST(valor_total_item AS DECIMAL(17, 2)), 0) AS valor_total_item,
        COALESCE(TRY_CAST(quantidade_devolvida AS INT), 0) AS quantidade_devolvida,
        COALESCE(TRY_CAST(peso_liquido AS DECIMAL(20, 5)), 0) AS peso_liquido_devolvido,

        -- Atributos Descritivos
        TRIM(UPPER(COALESCE(motivo, 'NÃO INFORMADO'))) AS motivo_devolucao,
        TRIM(UPPER(COALESCE(tipo_devolucao, 'NÃO INFORMADO'))) AS tipo_devolucao,
        TRIM(UPPER(COALESCE(observacao, ''))) AS observacao,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa para a mesma chave de devolução
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY empresa, numero_danfe_devolucao, data_devolucao, id_cliente, id_item, id_vendedor -- Agrupa pela chave composta
            ORDER BY
                data_devolucao DESC NULLS LAST -- Prioriza o registro com a data mais recente
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1