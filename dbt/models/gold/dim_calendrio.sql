-- dim_calendrio: dimensao tempo gerada via Jinja (sem source).
-- Grao: 1 linha por data entre 2024-01-01 e 2027-12-31.
-- Compartilhada entre todos os tenants (nao tem tenant_id).

{{ config(
    materialized = 'table',
    partitioned_by = none
) }}

with bounds as (
    select date '2024-01-01' as start_date, date '2027-12-31' as end_date
),

dates as (
    select cast(start_date as date) + s.n * interval '1' day as data
    from bounds
    cross join unnest(sequence(0, date_diff('day', start_date, end_date))) as s(n)
)

select
    cast(date_format(data, '%Y%m%d') as integer) as data_id,
    data                                          as dt_data,
    year(data)                                    as nr_ano,
    month(data)                                   as nr_mes,
    day(data)                                     as nr_dia,
    quarter(data)                                 as nr_trimestre,
    day_of_week(data)                             as nr_dia_semana,
    date_format(data, '%Y-%m')                    as nm_ano_mes,
    case when day_of_week(data) in (6, 7) then true else false end as fl_fim_de_semana
from dates
