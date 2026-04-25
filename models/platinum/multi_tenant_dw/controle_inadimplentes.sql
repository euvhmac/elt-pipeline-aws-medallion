-- depends_on: {{ ref('fct_titulo_financeiro') }}
 
-- Camada Platinum consome dados já enriquecidos da Gold
-- Todos os campos calculados (situacao_titulo, dias_atraso, faixas, etc.) 
-- já vêm da fct_titulo_financeiro
SELECT
    *
FROM {{ ref('fct_titulo_financeiro') }}
ORDER BY empresa, data_emissao