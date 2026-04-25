{{
  config(
    materialized='incremental',
    unique_key='sk_faturamento',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns',
    schema='gold__multi_tenant_dw'
  )
}}

WITH 
danfite AS (
    SELECT * FROM {{ ref('silver_dw_danfite') }}
    {% if is_incremental() %}
    WHERE data_criacao > (SELECT MAX(data_criacao) FROM {{ this }})
    {% endif %}
),

danfe AS (
    SELECT * FROM {{ ref('silver_dw_danfe') }}
    {% if is_incremental() %}
    WHERE data_emissao > (SELECT MAX(data_emissao) FROM {{ this }})
       OR data_criacao > (SELECT MAX(data_criacao) FROM {{ this }})
    {% endif %}
),

fct_faturamento AS (
    SELECT
        CONCAT(dft.empresa, '_', CAST(dft.id_danfe_numint AS STRING), '_', CAST(dft.id_item AS STRING)) AS sk_faturamento,
        dft.danfe_serie,
        dft.danfe_numero,
        dft.id_empresa,
        dft.id_filial,
        dft.id_unidade,
        dft.id_item,
        dft.id_cfop,
        dft.id_cfop_comp,
        dft.id_danfe_numint,
        dft.valor_base_icms,
        dft.valor_icms,
        dft.valor_icms_subs,
        dft.valor_icms_isento,
        dft.valor_base_icmsst,
        dft.valor_desconto,
        dft.valor_frete,
        dft.valor_seguro,
        dft.preco_unitario,
        dft.peso_total_item,
        dft.valor_total_item,
        dft.valor_liquido,
        dft.data_criacao,
        dft.empresa,
        df.status_danfe,
        df.data_emissao,
        df.id_regiao,
        df.id_pais_destino,
        df.sk_cidade_destino,
        df.id_pedido,
        df.sk_vendedor,
        df.sk_cliente,
        df.id_condpag,
        df.id_transportador,
        df.frete_porconta
    FROM danfite AS dft
    LEFT JOIN danfe AS df
        ON dft.sk_danfe_numint = df.sk_danfe
        AND dft.empresa = df.empresa
    WHERE 
        dft.id_cfop IN ('5101', '5102', '5118', '5124', '5401', '5405', '6101', '6102', '6118', '6124')
        AND df.status_danfe NOT IN ('SEM TITULO', 'CANCELADA')
)

SELECT * FROM fct_faturamento