{% macro vd_recon_schema_probe(relation) %}
  {# VD-4529: relation may be adapter-quoted; information_schema stores identifiers unquoted. #}
  {% set parts = vd_recon_relation_parts(relation) %}
  {% set query %}
    select column_name, data_type
    from information_schema.columns
    where table_catalog = '{{ parts[0] }}' and table_schema = '{{ parts[1] }}' and table_name = '{{ parts[2] }}'
    order by ordinal_position
  {% endset %}
  {% set results = run_query(query) %}
  {% set columns = [] %}
  {% for row in results.rows %}
    {% do columns.append({"name": row[0], "type": row[1]}) %}
  {% endfor %}
  {% set result = {"columns": columns} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
