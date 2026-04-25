{{
    config(
        materialized='incremental',
        unique_key='sk_cliente',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}


WITH unioned_sources AS (
    {{ union_sources('dw_cliente') }}
),

-- Aplica a limpeza, padronização, tipagem e renomeia as colunas para o padrão da camada Silver
cleaned AS (
    SELECT
        -- Criação da Chave Surrogate (Surrogate Key)
        CONCAT(empresa, '_', CAST(id_cliente AS STRING)) AS sk_cliente,

        -- NOVAS COLUNAS: Chaves Estrangeiras (Surrogate Keys) para relacionamento
        CONCAT(empresa, '_', CAST(id_vendedor AS STRING)) AS sk_vendedor,
        CONCAT(empresa, '_', CAST(id_tipocliente AS STRING)) AS sk_tipo_cliente,
        CONCAT(empresa, '_', CAST(id_cidade AS STRING)) AS sk_cidade,
        CONCAT(empresa, '_', CAST(id_rota AS STRING)) AS sk_rota,
        CONCAT(empresa, '_', CAST(id_ramo AS STRING)) AS sk_ramo,
        CONCAT(empresa, '_', CAST(id_rede AS STRING)) AS sk_rede,

        -- Identificadores e Chaves Estrangeiras (padronizados como STRING)
        CAST(id_cliente AS STRING) AS id_cliente,
        CAST(id_cidade AS STRING) AS id_cidade,
        CAST(id_ramo AS STRING) AS id_ramo,
        CAST(id_rede AS STRING) AS id_rede,
        CAST(id_vendedor AS STRING) AS id_vendedor,
        CAST(id_tipocliente AS STRING) AS id_tipocliente,
        CAST(id_rota AS STRING) AS id_rota,
        CAST(id_pais AS STRING) AS id_pais,
        CAST(id_categoria AS STRING) AS id_categoria,
        CAST(id_cnae AS STRING) AS id_cnae,

        -- Dados Cadastrais (limpeza de texto e padronização)
        TRIM(UPPER(COALESCE(razao_social, 'NÃO INFORMADO'))) AS razao_social,
        TRIM(UPPER(COALESCE(nome_fantasia, 'NÃO INFORMADO'))) AS nome_fantasia,
        TRIM(UPPER(COALESCE(inscricao_estadual, 'ISENTO'))) AS inscricao_estadual,
        TRIM(UPPER(COALESCE(inscricao_municipal, 'ISENTO'))) AS inscricao_municipal,
  
          -- CORREÇÃO APLICADA: Mapeamento de 0/1 para FÍSICA/JURÍDICA
        CASE
            WHEN TRIM(fisica_juridica) = '1' THEN 'JURÍDICA'
            WHEN TRIM(fisica_juridica) = '0' THEN 'FÍSICA'
            ELSE 'NÃO INFORMADO'
        END AS tipo_pessoa,

        -- CORREÇÃO APLICADA: Mapeamento de 0/1 para CPF/CNPJ
        NULLIF(REGEXP_REPLACE(COALESCE(cnpj, ''), '[^0-9]', ''), '') AS cnpj,
        NULLIF(REGEXP_REPLACE(COALESCE(cpf, ''), '[^0-9]', ''), '') AS cpf,

        -- Informações de Endereço
        TRIM(UPPER(COALESCE(endereco, 'NÃO INFORMADO'))) AS endereco,
        TRIM(UPPER(COALESCE(numero, 'S/N'))) AS numero,
        TRIM(UPPER(COALESCE(bairro, 'NÃO INFORMADO'))) AS bairro,
        NULLIF(REGEXP_REPLACE(COALESCE(cep, ''), '[^0-9]', ''), '') AS cep,
        TRIM(UPPER(COALESCE(ponto_referencia, ''))) AS ponto_referencia,

        -- Informações de Contato
        NULLIF(REGEXP_REPLACE(COALESCE(fone_principal, ''), '[^0-9]', ''), '') AS fone_principal,
        NULLIF(REGEXP_REPLACE(COALESCE(fone_secundario, ''), '[^0-9]', ''), '') AS fone_secundario,
        TRIM(LOWER(COALESCE(email, ''))) AS email,

        -- Datas
        CAST(data_fundacao AS DATE) AS data_fundacao,
        CAST(inicio_atividade AS DATE) AS data_inicio_atividade,
        CAST(data_inativacao AS DATE) AS data_inativacao,

        -- Status e Classificação
        TRIM(UPPER(COALESCE(situacao, '1'))) AS situacao_cliente, -- '1' Ativo, '0' Inativo...
        TRIM(UPPER(COALESCE(classificacao_abc, ''))) AS classificacao_abc,

        -- Condições Comerciais
        TRIM(UPPER(COALESCE(condicao_pagamento, ''))) AS condicao_pagamento,
        COALESCE(TRY_CAST(limite_credito AS DECIMAL(17, 2)), 0) AS limite_credito,
        CAST(codigo_lista AS INTEGER) AS codigo_lista_preco,
        CAST(tabela_preco AS INTEGER) AS tabela_preco,
        COALESCE(TRY_CAST(`perc_desc_fin` AS DECIMAL(17, 2)), 0) AS percentual_desconto_financeiro,
        COALESCE(TRY_CAST(`perc_desc_com` AS DECIMAL(17, 2)), 0) AS percentual_desconto_comercial,

        -- Flags (Campos BIT)
        CASE WHEN aplica_st = 1 THEN TRUE ELSE FALSE END AS aplica_substituicao_tributaria,
        CASE WHEN optante_simples = 1 THEN TRUE ELSE FALSE END AS is_optante_simples,

        -- Metadados
        empresa,
        CAST(data_alteracao AS TIMESTAMP) AS data_alteracao, -- Mantendo timestamp para desempate
        CAST(CURRENT_DATE() AS DATE) AS data_particao -- Coluna para particionamento da tabela

    FROM unioned_sources
),

-- Remove duplicatas intra-empresa, mantendo o registro mais recente
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY empresa, id_cliente -- Apenas duplicatas na mesma empresa e mesmo ID
            ORDER BY
                data_alteracao DESC NULLS LAST, -- Prioriza o registro com a alteração mais recente
                -- Adicionar outros critérios de desempate se necessário
                razao_social -- Critério final para garantir determinismo
        ) AS rn
    FROM cleaned
)

-- Seleção final dos dados desduplicados
-- O DBT com merge strategy já cuida de comparar com dados existentes via unique_key
SELECT
    * EXCEPT (rn)
FROM deduplicated
WHERE rn = 1