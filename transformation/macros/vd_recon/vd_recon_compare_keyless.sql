{% macro vd_recon_compare_keyless(baseline_relation, target_relation, column_pairs) %}
  {% set pii_columns = vd_recon_pii_columns(baseline_relation) %}
  {% set baseline_identity = vd_recon_keyless_identity(column_pairs, 'baseline', pii_columns) %}
  {% set target_identity = vd_recon_keyless_identity(column_pairs, 'target', pii_columns) %}

  {% set query %}
    with b as (select concat_ws(chr(31), {{ baseline_identity }}) as identity from {{ baseline_relation }}),
         t as (select concat_ws(chr(31), {{ target_identity }}) as identity from {{ target_relation }}),
         b_counts as (select identity, count(*) as n from b group by identity),
         t_counts as (select identity, count(*) as n from t group by identity)
    select
      coalesce(sum(greatest(coalesce(b_counts.n, 0) - coalesce(t_counts.n, 0), 0)), 0) as missing_from_target,
      coalesce(sum(greatest(coalesce(t_counts.n, 0) - coalesce(b_counts.n, 0), 0)), 0) as additional_in_target
    from b_counts
    full outer join t_counts on b_counts.identity = t_counts.identity
  {% endset %}
  {% set row = run_query(query).rows[0] %}
  {% set result = {"missing_from_target": row[0], "additional_in_target": row[1]} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
