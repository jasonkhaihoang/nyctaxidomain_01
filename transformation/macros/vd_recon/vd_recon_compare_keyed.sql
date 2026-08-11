{% macro vd_recon_compare_keyed(baseline_relation, target_relation, key_columns, column_pairs) %}
  {% set key_col = key_columns[0] %}
  {% set changed_condition %}
    {% for pair in column_pairs %}b.{{ pair.baseline_column }} is distinct from t.{{ pair.target_column }}{% if not loop.last %} or {% endif %}{% endfor %}
  {% endset %}

  {% set counts_query %}
    select
      (select count(*) from {{ baseline_relation }}) as baseline_rows,
      (select count(*) from {{ target_relation }}) as target_rows,
      (select count(distinct {{ key_col }}) from {{ baseline_relation }}) as baseline_keys,
      (select count(distinct {{ key_col }}) from {{ target_relation }}) as target_keys
  {% endset %}
  {% set counts = run_query(counts_query).rows[0] %}

  {# invalid_key_alignment: a row whose key is null, or whose key value is shared by more
     than one row on its own side — computed per side, then summed. This deliberately does
     NOT use total-minus-distinct (that undercounts once >2 rows share one key, and drops
     null keys from the distinct count entirely — verified against a synthetic duplicate/null
     fixture before writing this macro). #}
  {% set invalid_query %}
    with b_counted as (
      select {{ key_col }}, count(*) over (partition by {{ key_col }}) as key_count from {{ baseline_relation }}
    ),
    t_counted as (
      select {{ key_col }}, count(*) over (partition by {{ key_col }}) as key_count from {{ target_relation }}
    )
    select
      (select sum(case when {{ key_col }} is null then 1 when key_count > 1 then 1 else 0 end) from b_counted) as baseline_invalid,
      (select sum(case when {{ key_col }} is null then 1 when key_count > 1 then 1 else 0 end) from t_counted) as target_invalid
  {% endset %}
  {% set invalid = run_query(invalid_query).rows[0] %}

  {# classification: matched-key rows split into matching vs changed by a per-row OR across
     every mapped column pair — this is a DISTINCT-ROW count, never a sum of per-column
     conflict events (a row differing in two mapped columns is still one changed row). #}
  {% set classification_query %}
    with b as (select * from {{ baseline_relation }}),
         t as (select * from {{ target_relation }}),
         matched as (
           select b.{{ key_col }} as key_val, ({{ changed_condition }}) as is_changed
           from b join t on b.{{ key_col }} = t.{{ key_col }}
         )
    select
      (select count(*) from matched) as matched_keys,
      (select sum(case when is_changed then 1 else 0 end) from matched) as changed_rows,
      (select sum(case when not is_changed then 1 else 0 end) from matched) as matching_rows,
      (select count(*) from b where b.{{ key_col }} not in (select {{ key_col }} from t where {{ key_col }} is not null) or (b.{{ key_col }} is null)) as missing_from_target,
      (select count(*) from t where t.{{ key_col }} not in (select {{ key_col }} from b where {{ key_col }} is not null) or (t.{{ key_col }} is null)) as additional_in_target
  {% endset %}
  {% set cls = run_query(classification_query).rows[0] %}

  {% set column_conflicts = [] %}
  {% for pair in column_pairs %}
    {% set conflict_query %}
      with b as (select * from {{ baseline_relation }}),
           t as (select * from {{ target_relation }})
      select
        sum(case when b.{{ pair.baseline_column }} is not null and t.{{ pair.target_column }} is not null
                  and b.{{ pair.baseline_column }} is distinct from t.{{ pair.target_column }} then 1 else 0 end) as conflict_count,
        sum(case when (b.{{ pair.baseline_column }} is null) != (t.{{ pair.target_column }} is null)
                  and b.{{ key_col }} is not null and t.{{ key_col }} is not null then 1 else 0 end) as one_sided_null_count
      from b
      join t on b.{{ key_col }} = t.{{ key_col }}
    {% endset %}
    {% set row = run_query(conflict_query).rows[0] %}
    {% do column_conflicts.append({"column": pair.target_column, "conflict_count": row[0], "one_sided_null_count": row[1]}) %}
  {% endfor %}

  {% set result = {
    "row_count": {"baseline": counts[0], "target": counts[1]},
    "key_count": {"baseline": counts[2], "target": counts[3]},
    "classification": {
      "matching": cls[2],
      "missing_from_target": cls[3],
      "additional_in_target": cls[4],
      "changed": cls[1]
    },
    "invalid_key_alignment": (invalid[0] | int) + (invalid[1] | int),
    "column_conflicts": column_conflicts
  } %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
