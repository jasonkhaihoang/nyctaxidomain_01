{% macro vd_recon_probe_boundaries(relation, column) %}
  {% set query %}
    select min({{ column }}) as min_val, max({{ column }}) as max_val, count(*) as row_count
    from {{ relation }}
  {% endset %}
  {% set results = run_query(query) %}
  {% set row = results.rows[0] %}
  {% set result = {"min": row[0] | string, "max": row[1] | string, "count": row[2]} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
