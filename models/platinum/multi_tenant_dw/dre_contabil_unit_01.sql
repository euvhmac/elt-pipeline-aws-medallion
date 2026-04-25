-- depends_on: {{ ref('dre_contabil') }}

SELECT
    *
FROM
    {{ ref('dre_contabil') }}
WHERE
    empresa = 'Unit_01'