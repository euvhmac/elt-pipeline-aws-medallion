{{
    config(
        materialized='incremental',
        unique_key='sk_danfite',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

WITH unioned_sources AS (
    {{ union_sources('dw_danfite') }}
),

-- Aplica a limpeza, padronização, tipagem e cria as chaves para relacionamento
cleaned AS (
    SELECT
        -- Chaves Primárias (Surrogate Keys) - composta por empresa + danfe_numero + id_danfe_numint + id_item + sequencia_item
        CONCAT(
            empresa, '_',
            CAST(danfe_numero AS STRING), '_',
            CAST(id_danfe_numint AS STRING), '_',
            CAST(id_item AS STRING), '_',
            CAST(sequencia_item AS STRING)
        ) AS sk_danfite,
        CONCAT(empresa, '_', CAST(id_danfe_numint AS STRING)) AS sk_danfe_numint,
        CONCAT(empresa, '_', CAST(danfe_numero AS STRING)) AS sk_danfe_numero,
        CONCAT(empresa, '_', CAST(id_empresa AS STRING)) AS sk_empresa,
        CONCAT(empresa, '_', CAST(id_filial AS STRING)) AS sk_filial,
        CONCAT(empresa, '_', CAST(id_unidade AS STRING)) AS sk_unidade,

        -- Colunas selecionadas
        danfe_serie,
        danfe_numero,
        id_empresa,
        id_filial,
        id_unidade,
        id_item,
        sequencia_item,
        id_cfop,
        id_cfop_comp,
        id_danfe_numint,

        -- Fatos e Métricas com conversão de tipo
        CAST(valor_base_icms AS DECIMAL(18, 2)) AS valor_base_icms,
        CAST(valor_icms AS DECIMAL(18, 2)) AS valor_icms,
        CAST(valor_icms_subs AS DECIMAL(18, 2)) AS valor_icms_subs,
        CAST(valor_icms_isento AS DECIMAL(18, 2)) AS valor_icms_isento,
        CAST(valor_base_icmsst AS DECIMAL(18, 2)) AS valor_base_icmsst,
        CAST(valor_desconto AS DECIMAL(18, 2)) AS valor_desconto,
        CAST(valor_frete AS DECIMAL(18, 2)) AS valor_frete,
        CAST(valor_seguro AS DECIMAL(18, 2)) AS valor_seguro,
        CAST(preco_unitario AS DECIMAL(18, 4)) AS preco_unitario,
        CAST(peso_total_item AS DECIMAL(18, 4)) AS peso_total_item,
        CAST(valor_total_item AS DECIMAL(18, 2)) AS valor_total_item,
        CAST(valor_liquido AS DECIMAL(18, 2)) AS valor_liquido,

        -- Datas com conversão de tipo
        CAST(data_criacao AS DATE) AS data_criacao,

        -- Metadados
        empresa

    FROM unioned_sources
)

SELECT * FROM cleaned