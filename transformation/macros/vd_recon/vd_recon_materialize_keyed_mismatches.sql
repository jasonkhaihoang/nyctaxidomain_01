{% macro vd_recon_materialize_keyed_mismatches(baseline_relation, target_relation, key_columns, column_pairs, run_id, carry_columns=[]) %}
  {% set key_col = key_columns[0] %}
  {% set mismatch_table %}{{ target.database }}.{{ target.schema }}.vd_recon_mismatch_{{ run_id }}{% endset %}
  {% set changed_condition %}
    {% for pair in column_pairs %}b.{{ pair.baseline_column }} is distinct from t.{{ pair.target_column }}{% if not loop.last %} or {% endif %}{% endfor %}
  {% endset %}

  {# Each side's mapped columns are emitted with an explicit baseline_/target_ prefix over the
     TARGET column name, which is canonical. The previous `b.* exclude(key)` / `t.* exclude(key)`
     form produced two columns of the same name whenever both sides shared one (this fixture's
     own `status`), leaving column-scoped predicates unable to reference either side.

     baseline_present/target_present are what let vd_recon_categorize_keyed tell a PRESENCE class
     (a key on one side only) from a VALUE delta. Without them, `baseline_X is distinct from
     target_X` reports a baseline-only row as one spurious cell per mapped column, erasing the
     presence class the design's difference-unit table defines.

     carry_columns are unmapped columns (order_date, internal_notes) kept for stage-3 localization
     — the design's stage 3 groups by "one candidate base column, boundary, or Target operator",
     and an unmapped boundary column is exactly what a temporal hypothesis needs. The previous
     b.*/t.* form carried them incidentally; dropping to mapped-pairs-only would have removed that
     ground silently. #}
  {% set create_query %}
    create table {{ mismatch_table }} as
    with b as (select * from {{ baseline_relation }}),
         t as (select * from {{ target_relation }})
    select coalesce(b.{{ key_col }}, t.{{ key_col }}) as {{ key_col }},
           (b.{{ key_col }} is not null) as baseline_present,
           (t.{{ key_col }} is not null) as target_present
           {% for pair in column_pairs %},
           b.{{ pair.baseline_column }} as baseline_{{ pair.target_column }},
           t.{{ pair.target_column }} as target_{{ pair.target_column }}
           {% endfor %}
           {% for col in carry_columns %},
           b.{{ col }} as baseline_{{ col }},
           t.{{ col }} as target_{{ col }}
           {% endfor %}
    from b
    full outer join t on b.{{ key_col }} = t.{{ key_col }}
    where b.{{ key_col }} is null
       or t.{{ key_col }} is null
       or ({{ changed_condition }})
  {% endset %}
  {% do run_query(create_query) %}

  {% set count_query %}select count(*) as n from {{ mismatch_table }}{% endset %}
  {% set n = run_query(count_query).rows[0][0] %}

  {% set result = {"mismatch_table_ref": mismatch_table, "row_count": n} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
