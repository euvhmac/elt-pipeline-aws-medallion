-- depends_on: {{ ref('d_estrutura_dre_contabil_unit_01') }}
-- depends_on: {{ ref('d_estrutura_dre_contabil_unit_02') }}
{{
    config(materialized='table')
}}

with estrutura_unit_01 as (
    select 
        cast(cod_conta as string) as cod_conta,
        cast(Ranking as string) as ranking,
        cast(Descricao_Conta as string) as descricao_conta,
        cast(Nivel_0 as string) as nivel_0,
        cast(Nivel_1 as string) as nivel_1,
        cast(Nivel_2 as string) as nivel_2,
        cast(Fator_Sinal as string) as fator_sinal,
        cast(Tipo_Linha as string) as tipo_linha,
        cast(Ordem_Exibicao as string) as ordem_exibicao,
        cast(ID_Nivel0 as string) as id_nivel0,
        cast(ID_Nivel1 as string) as id_nivel1,
        cast(ID_Nivel2 as string) as id_nivel2,
        'Unit_01' as empresa 
    from {{ ref('d_estrutura_dre_contabil_unit_01') }}
),
estrutura_unit_02 as (
    select 
        cast(Cod_Cont as string) as cod_conta,
        cast(Ranking as string) as ranking,
        cast(Descricao_Conta as string) as descricao_conta,
        cast(Nivel_0 as string) as nivel_0,
        cast(Nivel_1 as string) as nivel_1,
        cast(Nivel_2 as string) as nivel_2,
        cast(Fator_Sinal as string) as fator_sinal,
        cast(Tipo_Linha as string) as tipo_linha,
        cast(Ordem_Exibicao as string) as ordem_exibicao,
        cast(ID_Nivel_0 as string) as id_nivel0,
        cast(ID_Nivel_1 as string) as id_nivel1,
        cast(ID_Nivel_2 as string) as id_nivel2,
        'Unit_02' as empresa 
    from {{ ref('d_estrutura_dre_contabil_unit_02') }}
),
estrutura as (
    select * from estrutura_unit_01
    union all
    select * from estrutura_unit_02
)

select
    cod_conta as id_conta,
    ranking,
    descricao_conta,
    nivel_0,
    nivel_1,
    nivel_2,
    fator_sinal,
    tipo_linha,
    ordem_exibicao,
    id_nivel0,
    id_nivel1,
    id_nivel2,
    empresa
from estrutura
order by empresa, ranking