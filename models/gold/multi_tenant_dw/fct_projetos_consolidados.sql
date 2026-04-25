-- depends_on: {{ ref('silver_dw_projeto_sup') }}
 
with projetos_base as (
 
    select
        id_empresa,
        id_unidade,
        id_projeto,
        id_projeto_pai,
        ano,
        mes,
        situacao,
        usuario,
        id_conta,
        descricao_projeto,
        fase,
        status_projeto,
        importancia,
        id_centro_custo,
        nome_projeto,
        justificativa,
        valor_previsto_seq1,
        valor_previsto_seq2,
        valor_previsto_seq3,
        valor_previsto_seq4,
        valor_previsto_seq5,
        valor_realizado,
        data_encerramento,
        valor_aprovado_ordem_compra,
        data_cadastro_projeto,
        data_previsao_encerramento,
        -- Usar o campo empresa já disponível na camada silver
        empresa
    from {{ ref('silver_dw_projeto_sup') }}
 
),
 
-- Self-join para obter a descrição do projeto pai
projetos_com_pai as (
 
    select
        pb.id_empresa,
        pb.id_unidade,
        pb.id_projeto,
        initcap(pb.nome_projeto) as nome_projeto, -- Nome do projeto
        initcap(pai.nome_projeto) as nome_projeto_pai, -- Nome do projeto pai
        pb.id_projeto_pai,
        initcap(pai.descricao_projeto) as descricao_projeto_pai, -- Descrição do projeto pai
        initcap(pb.descricao_projeto) as descricao_projeto,
        pb.fase,
        pb.status_projeto,
        pb.importancia,
        pb.ano,
        pb.mes,
        -- Concatena ano e mês para criar uma data no formato 'YYYY-MM-01'
        concat(pb.ano, '-', lpad(pb.mes, 2, '0'), '-01') as data_referencia,
        pb.data_cadastro_projeto,
        pb.data_previsao_encerramento,
        pb.data_encerramento,
        pb.situacao,
        pb.usuario,
        pb.id_conta,
        pb.id_centro_custo,
        pb.justificativa,
        pb.valor_previsto_seq1,
        pb.valor_previsto_seq2,
        pb.valor_previsto_seq3,
        pb.valor_previsto_seq4,
        pb.valor_previsto_seq5,
        pb.valor_realizado,
        pb.valor_aprovado_ordem_compra,
        pb.empresa
    from projetos_base as pb
    left join projetos_base as pai
        on pb.id_projeto_pai = pai.id_projeto
        and pb.id_empresa = pai.id_empresa
 
)
 
select * from projetos_com_pai