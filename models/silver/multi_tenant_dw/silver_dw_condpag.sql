{{
    config(
        materialized='incremental',
        unique_key='sk_condicao_pagamento',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}


WITH unioned_sources AS (
    {{ union_sources('dw_condpag') }}
),

-- Aplica a limpeza, padronização e tipagem das colunas
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_empresa AS STRING), '_', CAST(id_condpag AS STRING)) AS sk_condicao_pagamento,

        -- Identificadores (padronizados como STRING)
        CAST(id_condpag AS STRING) AS id_condicao_pagamento,
        CAST(id_empresa AS STRING) AS id_empresa_original,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(condicao_pagto, 'NÃO INFORMADO'))) AS descricao_condicao_pagamento,
        
        -- Extração da quantidade de dias da condição de pagamento
        CASE
            -- Se contém múltiplos números (ex: 14/21/28 ou 18X19X20X21X22), calcula a média de todos
            WHEN condicao_pagto RLIKE '\\d+[/X]\\d+' THEN
                CAST(
                    (
                        -- Soma todos os números encontrados
                        COALESCE(TRY_CAST(NULLIF(REGEXP_EXTRACT(condicao_pagto, '(\\d+)', 0), '') AS DOUBLE), 0) +
                        COALESCE(TRY_CAST(NULLIF(REGEXP_EXTRACT(condicao_pagto, '[/X](\\d+)', 1), '') AS DOUBLE), 0) +
                        COALESCE(TRY_CAST(NULLIF(REGEXP_EXTRACT(condicao_pagto, '[/X]\\d+[/X](\\d+)', 1), '') AS DOUBLE), 0) +
                        COALESCE(TRY_CAST(NULLIF(REGEXP_EXTRACT(condicao_pagto, '[/X]\\d+[/X]\\d+[/X](\\d+)', 1), '') AS DOUBLE), 0) +
                        COALESCE(TRY_CAST(NULLIF(REGEXP_EXTRACT(condicao_pagto, '[/X]\\d+[/X]\\d+[/X]\\d+[/X](\\d+)', 1), '') AS DOUBLE), 0)
                    ) / 
                    (
                        -- Conta quantos números existem
                        CASE 
                            WHEN condicao_pagto RLIKE '\\d+[/X]\\d+[/X]\\d+[/X]\\d+[/X]\\d+' THEN 5
                            WHEN condicao_pagto RLIKE '\\d+[/X]\\d+[/X]\\d+[/X]\\d+' THEN 4
                            WHEN condicao_pagto RLIKE '\\d+[/X]\\d+[/X]\\d+' THEN 3
                            WHEN condicao_pagto RLIKE '\\d+[/X]\\d+' THEN 2
                            ELSE 1
                        END
                    )
                AS DECIMAL(10,2))
            -- Se contém apenas um número, extrai o primeiro número encontrado
            WHEN condicao_pagto RLIKE '\\d+' THEN
                CAST(REGEXP_EXTRACT(condicao_pagto, '(\\d+)') AS DECIMAL(10,2))
            -- Se não houver número, retorna 0
            ELSE 0
        END AS quantidade_dias,
        
        -- Metadados
        empresa

    FROM unioned_sources
),

-- Remove duplicatas dentro do batch atual
-- O DBT com merge strategy já cuida de comparar com dados existentes via unique_key
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sk_condicao_pagamento
            ORDER BY descricao_condicao_pagamento DESC -- Prioriza descrições mais completas
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados desduplicados
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1