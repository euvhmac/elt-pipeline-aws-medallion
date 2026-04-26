-- Singular test: garante que vlr_total do item bate com qtd_vendida * vlr_unitario.
-- Tolerancia: 1 centavo por arredondamento.
-- Falha = retorna linhas; sucesso = zero linhas.

select
    tenant_id,
    item_id,
    qtd_vendida,
    vlr_unitario,
    vlr_total,
    abs(vlr_total - (qtd_vendida * vlr_unitario)) as divergencia
from {{ ref('fct_vendas') }}
where abs(vlr_total - (qtd_vendida * vlr_unitario)) > 0.01
