{#
  Macro: union_sources
  
  Gera UNION ALL de uma mesma tabela fonte em todos os tenants configurados.
  A lista de tenants é lida da variável `tenants` definida em dbt_project.yml.
  
  Para adicionar ou remover um tenant, edite apenas `vars.tenants` no dbt_project.yml
  — nenhum modelo SQL precisa ser alterado.
  
  Parâmetros:
    table_name (str) : nome da tabela no schema Bronze (ex: 'dw_vendas')
    columns    (list): colunas a selecionar; padrão ['*'] para todas

  Uso nos modelos Silver:
    WITH unioned_sources AS (
        {{ union_sources('dw_vendas') }}
    ),
#}
{% macro union_sources(table_name, columns=['*']) %}
    {%- set tenants   = var('tenants') -%}
    {%- set col_list  = columns | join(', ') -%}

    {%- for tenant in tenants %}
    SELECT
        {{ col_list }},
        '{{ tenant.label }}' AS empresa
    FROM {{ source('bronze__' + tenant.id, table_name) }}
        {%- if not loop.last %}
    UNION ALL
        {%- endif %}
    {%- endfor %}
{% endmacro %}
