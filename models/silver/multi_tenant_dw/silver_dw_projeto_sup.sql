with unioned_sources as (
    {{ union_sources('dw_projeto_sup') }}
),

cleaned as (

    select
        -- Chaves primárias e de negócios (tratando 0 como nulo)
        id_empresa,
        id_unidade,
        id_projeto,
        case when id_projeto_pai = 0 then null else id_projeto_pai end as id_projeto_pai,
        case when id_safra = 0 then null else id_safra end as id_safra,
        case when id_centro_custo = 0 then null else id_centro_custo end as id_centro_custo, -- CORRIGIDO
        case when id_conta = 0 then null else id_conta end as id_conta,
        case when id_analitico = 0 then null else id_analitico end as id_analitico,

        -- Datas e Horas (tratando 0 e datas inválidas como nulo)
        case when ano = 0 then null else ano end as ano,
        case when mes = 0 then null else mes end as mes,
        case when data_abertura = '1900-01-01' then null else data_abertura end as data_abertura,
        case when data_encerramento = '1900-01-01' then null else data_encerramento end as data_encerramento,
        case when data_previsao_encerramento = '1900-01-01' then null else data_previsao_encerramento end as data_previsao_encerramento,
        case when data_cadastro_projeto = '1900-01-01' then null else data_cadastro_projeto end as data_cadastro_projeto,
        case when hora_cadstro_projeto = 0 then null else hora_cadstro_projeto end as hora_cadastro_projeto,
        case when data_desbloqueio_seq1 = '1900-01-01' then null else data_desbloqueio_seq1 end as data_desbloqueio_seq1,
        case when data_desbloqueio_seq2 = '1900-01-01' then null else data_desbloqueio_seq2 end as data_desbloqueio_seq2,
        case when data_desbloqueio_seq3 = '1900-01-01' then null else data_desbloqueio_seq3 end as data_desbloqueio_seq3,
        case when data_desbloqueio_seq4 = '1900-01-01' then null else data_desbloqueio_seq4 end as data_desbloqueio_seq4,
        case when data_desbloqueio_seq5 = '1900-01-01' then null else data_desbloqueio_seq5 end as data_desbloqueio_seq5,
        case when data_desbloqueio_seq6 = '1900-01-01' then null else data_desbloqueio_seq6 end as data_desbloqueio_seq6,
        case when hora_desbloqueio_seq1 = 0 then null else hora_desbloqueio_seq1 end as hora_desbloqueio_seq1,
        case when hora_desbloqueio_seq2 = 0 then null else hora_desbloqueio_seq2 end as hora_desbloqueio_seq2,
        case when hora_desbloqueio_seq3 = 0 then null else hora_desbloqueio_seq3 end as hora_desbloqueio_seq3,
        case when hora_desbloqueio_seq4 = 0 then null else hora_desbloqueio_seq4 end as hora_desbloqueio_seq4,
        case when hora_desbloqueio_seq5 = 0 then null else hora_desbloqueio_seq5 end as hora_desbloqueio_seq5,
        case when hora_desbloqueio_seq6 = 0 then null else hora_desbloqueio_seq6 end as hora_desbloqueio_seq6,
        case when data_atualizao_dw = '1900-01-01' then null else data_atualizao_dw end as data_atualizacao_dw, -- Renomeando a coluna
        case when data_criacao = '1900-01-01' then null else data_criacao end as data_criacao,

        -- Descrições e Textos (tratando strings vazias como nulo e padronizando)
        case when trim(importancia) = '' then null else trim(importancia) end as importancia,
        case when trim(gravidade) = '' then null else trim(gravidade) end as gravidade,
        case when trim(justificativa) = '' then null else trim(justificativa) end as justificativa,
        case when trim(informacoes_adicionais) = '' then null else trim(informacoes_adicionais) end as informacoes_adicionais,
        case when trim(descricao_projeto) = '' then null else trim(descricao_projeto) end as descricao_projeto,
        case when trim(usuario) = '' then null else trim(usuario) end as usuario,
        case when trim(usuario_aprovador_seq1) = '' then null else trim(usuario_aprovador_seq1) end as usuario_aprovador_seq1,
        case when trim(usuario_aprovador_seq2) = '' then null else trim(usuario_aprovador_seq2) end as usuario_aprovador_seq2,
        case when trim(usuario_aprovador_seq3) = '' then null else trim(usuario_aprovador_seq3) end as usuario_aprovador_seq3,
        case when trim(usuario_aprovador_seq4) = '' then null else trim(usuario_aprovador_seq4) end as usuario_aprovador_seq4,
        case when trim(usuario_aprovador_seq5) = '' then null else trim(usuario_aprovador_seq5) end as usuario_aprovador_seq5,
        case when trim(usuario_aprovador_seq6) = '' then null else trim(usuario_aprovador_seq6) end as usuario_aprovador_seq6,
        case when trim(observacao_aprovacao_seq1) = '' then null else trim(observacao_aprovacao_seq1) end as observacao_aprovacao_seq1,
        case when trim(observacao_aprovacao_seq2) = '' then null else trim(observacao_aprovacao_seq2) end as observacao_aprovacao_seq2,
        case when trim(observacao_aprovacao_seq3) = '' then null else trim(observacao_aprovacao_seq3) end as observacao_aprovacao_seq3,
        case when trim(observacao_aprovacao_seq4) = '' then null else trim(observacao_aprovacao_seq4) end as observacao_aprovacao_seq4,
        case when trim(observacao_aprovacao_seq5) = '' then null else trim(observacao_aprovacao_seq5) end as observacao_aprovacao_seq5,
        case when trim(observacao_aprovacao_seq6) = '' then null else trim(observacao_aprovacao_seq6) end as observacao_aprovacao_seq6,
        case when trim(situacao) = '' then null else trim(upper(situacao)) end as situacao,
        case when trim(lavoura) = '' then null else trim(upper(lavoura)) end as lavoura,
        case when trim(status_projeto) = '' then null else trim(upper(status_projeto)) end as status_projeto,
        case when trim(custo_fixo) = '' then null else trim(upper(custo_fixo)) end as custo_fixo,
        case when trim(usuario_envolvido1) = '' then null else trim(usuario_envolvido1) end as usuario_envolvido1,
        case when trim(usuario_envolvido2) = '' then null else trim(usuario_envolvido2) end as usuario_envolvido2,
        case when trim(usuario_envolvido3) = '' then null else trim(usuario_envolvido3) end as usuario_envolvido3,
        case when trim(usuario_envolvido4) = '' then null else trim(usuario_envolvido4) end as usuario_envolvido4,
        case when trim(usuario_envolvido5) = '' then null else trim(usuario_envolvido5) end as usuario_envolvido5,
        case when trim(fase) = '' then null else trim(fase) end as fase,
        case when trim(urgencia) = '' then null else trim(urgencia) end as urgencia,
        case when trim(objetivo) = '' then null else trim(objetivo) end as objetivo,
        case when trim(alinhamento_estrategico) = '' then null else trim(alinhamento_estrategico) end as alinhamento_estrategico,
        case when trim(credita_pis_cofins) = '' then null else trim(upper(credita_pis_cofins)) end as credita_pis_cofins,
        case when trim(nome_projeto) = '' then null else trim(nome_projeto) end as nome_projeto,

        -- Valores Numéricos / Financeiros (tratando 0 como nulo)
        case when sequencia_aprovacao_atual = 0 then null else sequencia_aprovacao_atual end as sequencia_aprovacao_atual,
        case when valor_previsto_seq1 = 0 then null else valor_previsto_seq1 end as valor_previsto_seq1,
        case when valor_previsto_seq2 = 0 then null else valor_previsto_seq2 end as valor_previsto_seq2,
        case when valor_previsto_seq3 = 0 then null else valor_previsto_seq3 end as valor_previsto_seq3,
        case when valor_previsto_seq4 = 0 then null else valor_previsto_seq4 end as valor_previsto_seq4,
        case when valor_previsto_seq5 = 0 then null else valor_previsto_seq5 end as valor_previsto_seq5,
        case when valor_previsto_seq6 = 0 then null else valor_previsto_seq6 end as valor_previsto_seq6,
        case when valor_aprovado_ordem_compra = 0 then null else valor_aprovado_ordem_compra end as valor_aprovado_ordem_compra,
        case when valor_previsto = 0 then null else valor_previsto end as valor_previsto,
        case when valor_realizado = 0 then null else valor_realizado end as valor_realizado,
        
        -- Campo de origem da empresa
        empresa

    from unioned_sources
)

select * from cleaned