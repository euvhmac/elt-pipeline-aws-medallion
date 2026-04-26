-- Teste singular: inadimplentes nao podem ter nr_dias_atraso negativo.
-- nr_dias_atraso deve ser >= 0 para todos os registros da Platinum.

select
    tenant_id,
    titulo_id,
    tipo_titulo,
    nr_dias_atraso
from {{ ref('controle_inadimplentes') }}
where nr_dias_atraso < 0
