{% macro vd_recon_aggregate_evidence(mismatch_table_ref, column, pii=false) %}
  {% if pii %}
    {% set query %}
      select count(*) as n, count({{ column }}) as non_null_n
      from {{ mismatch_table_ref }}
    {% endset %}
    {% set row = run_query(query).rows[0] %}
    {% set measures = [
      {"measure": "count", "value": row[1]},
      {"measure": "rate", "value": (row[1] / row[0]) if row[0] > 0 else 0}
    ] %}
  {% else %}
    {% set query %}
      select count({{ column }}) as non_null_n, min({{ column }}) as min_val, max({{ column }}) as max_val, count(distinct {{ column }}) as distinct_n
      from {{ mismatch_table_ref }}
    {% endset %}
    {% set row = run_query(query).rows[0] %}
    {% set measures = [
      {"measure": "count", "value": row[0]},
      {"measure": "min", "value": row[1] | string},
      {"measure": "max", "value": row[2] | string},
      {"measure": "distinct_count", "value": row[3]}
    ] %}
  {% endif %}
  {% set result = {"column": column, "measures": measures} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
