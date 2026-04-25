{{
    config(
        materialized='incremental',
        unique_key='sk_danfe',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}


WITH unioned_sources AS (
    {{ union_sources('dw_danfe') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chave Primária (Surrogate Key) - composta por empresa + danfe_numero + id_danfe_numint + id_pedido
        CONCAT(
            empresa, '_',
            COALESCE(CAST(danfe_numero AS STRING), '-1'), '_',
            COALESCE(CAST(id_danfe_numint AS STRING), '-1'), '_',
            COALESCE(CAST(id_pedido AS STRING), '-1')
        ) AS sk_danfe,

        -- Chaves Estrangeiras (Surrogate Keys) para relacionamento
        CONCAT(empresa, '_', CAST(id_cliente AS STRING)) AS sk_cliente,
        CONCAT(empresa, '_', CAST(id_vendedor AS STRING)) AS sk_vendedor,
        CONCAT(empresa, '_', CAST(id_cidade_destino AS STRING)) AS sk_cidade_destino,

        -- Colunas adicionadas
        id_regiao,
        id_pais_destino,
        id_condpag,
        id_transportador,
        id_filial,
        id_empresa,
        id_unidade,
        frete_porconta,

        -- Identificadores do Documento
        CAST(danfe_numero AS STRING) AS numero_danfe,
        CAST(id_danfe_numint AS STRING) AS id_danfe_numint,
        CAST(danfe_serie AS STRING) AS serie_danfe,
        CAST(id_pedido AS STRING) AS id_pedido,
        
        -- Datas Principais
        TRY_CAST(data_emissao AS DATE) AS data_emissao,
        TRY_CAST(data_saida AS DATE) AS data_saida,
        TRY_CAST(data_entrada AS DATE) AS data_entrada,

        -- Valores Monetários Principais
        COALESCE(TRY_CAST(valor_total AS DECIMAL(17, 2)), 0) AS valor_total,
        COALESCE(TRY_CAST(valor_mercadoria AS DECIMAL(17, 2)), 0) AS valor_mercadoria,
        COALESCE(TRY_CAST(valor_frete AS DECIMAL(17, 2)), 0) AS valor_frete,
        COALESCE(TRY_CAST(valor_desconto AS DECIMAL(17, 2)), 0) AS valor_desconto,
        COALESCE(TRY_CAST(valor_icms AS DECIMAL(17, 2)), 0) AS valor_icms,
        COALESCE(TRY_CAST(valor_ipi AS DECIMAL(17, 2)), 0) AS valor_ipi,
        COALESCE(TRY_CAST(valor_cmv AS DECIMAL(17, 2)), 0) AS valor_custo_mercadoria_vendida,
        
        -- Pesos e Volumes
        COALESCE(TRY_CAST(peso_bruto AS DECIMAL(17, 3)), 0) AS peso_bruto,
        COALESCE(TRY_CAST(peso_liquido AS DECIMAL(17, 3)), 0) AS peso_liquido,
        COALESCE(TRY_CAST(volumes AS DECIMAL(17, 2)), 0) AS volumes,

        -- Status e Tipos
        CASE
            WHEN danfe_status = 0 THEN 'INCOMPLETA'
            WHEN danfe_status = 1 THEN 'SEM TITULO'
            WHEN danfe_status = 2 THEN 'COM TITULO'
            WHEN danfe_status = 3 THEN 'IMPLANTADA'
            WHEN danfe_status = 4 THEN 'DEVOLUCAO PARCIAL'
            WHEN danfe_status = 5 THEN 'DEVOLUCAO TOTAL'
            WHEN danfe_status = 9 THEN 'CANCELADA'
            ELSE 'DESCONHECIDO'
        END AS status_danfe,
        CASE
            WHEN entrada_ou_saida = 'E' THEN 'ENTRADA'
            WHEN entrada_ou_saida = 'S' THEN 'SAIDA'
            ELSE 'NÃO INFORMADO'
        END AS tipo_movimento,

        -- Metadados
        empresa,
        TRY_CAST(data_criacao AS TIMESTAMP) AS data_criacao -- Usado para desempate

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa para a mesma chave de DANFE
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY empresa, numero_danfe, id_danfe_numint, id_pedido -- Agrupa pela chave composta
            ORDER BY
                data_criacao DESC NULLS LAST -- Prioriza o registro com a criação mais recente
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados, aplicando o filtro de desduplicação
SELECT
    sk_danfe,
    sk_cliente,
    sk_vendedor,
    sk_cidade_destino,
    id_regiao,
    id_pais_destino,
    id_condpag,
    id_transportador,
    frete_porconta,
    numero_danfe,
    id_danfe_numint,
    serie_danfe,
    id_pedido,
    data_emissao,
    data_saida,
    data_entrada,
    valor_total,
    valor_mercadoria,
    valor_frete,
    valor_desconto,
    valor_icms,
    valor_ipi,
    valor_custo_mercadoria_vendida,
    peso_bruto,
    peso_liquido,
    volumes,
    status_danfe,
    tipo_movimento,
    empresa,
    data_criacao
FROM deduplicated
WHERE rn = 1
