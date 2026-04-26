-- Teste singular: todos os tenants da dre_contabil_unit_01 devem ser 'unit_01'.
-- Detecta vazamento de dados de outras unidades na visao Platinum.

select
    tenant_id,
    count(*) as qt_registros_invalidos
from {{ ref('dre_contabil_unit_01') }}
where tenant_id != 'unit_01'
group by tenant_id
