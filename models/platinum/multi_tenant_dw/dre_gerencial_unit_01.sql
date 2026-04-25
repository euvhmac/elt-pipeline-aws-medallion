-- depends_on: {{ ref('dre_gerencial') }}

SELECT
    *
FROM
    {{ ref('dre_gerencial') }}
WHERE
    empresa = 'Unit_01'