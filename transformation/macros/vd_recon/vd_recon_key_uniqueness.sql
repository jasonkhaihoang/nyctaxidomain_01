{% macro vd_recon_key_uniqueness(relation, key_columns) %}
  {% set key_expr = key_columns | join(', ') %}
  {% set query %}
    select
      count(*) as total,
      count(distinct ({{ key_expr }})) as distinct_count,
      sum(case when {{ key_columns | map('trim') | join(' is null or ') }} is null then 1 else 0 end) as null_count
    from {{ relation }}
  {% endset %}
  {% set results = run_query(query) %}
  {% set row = results.rows[0] %}
  {% set result = {"total": row[0], "distinct": row[1], "nulls": row[2]} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
