-- platinum.dim_estrutura_dre_contabil_unit_02
-- VIEW com a estrutura da DRE apenas para a empresa Unit_02.

SELECT
    id_conta,
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
    id_nivel2
FROM
    {{ ref('dim_estrutura_dre_contabil') }}
WHERE
    empresa = 'Unit_02'