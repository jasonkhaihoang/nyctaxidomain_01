{% macro vd_recon_materialize_keyed_mismatches(baseline_relation, target_relation, key_columns, column_pairs, run_id, carry_columns=[], source_relations=[]) %}
  {% set key_col = key_columns[0] %}
  {% set mismatch_table %}{{ target.database }}.{{ target.schema }}.vd_recon_mismatch_{{ run_id }}{% endset %}
  {% set changed_condition %}
    {% for pair in column_pairs %}b.{{ pair.baseline_column }} is distinct from t.{{ pair.target_column }}{% if not loop.last %} or {% endif %}{% endfor %}
  {% endset %}

  {# DC-30 (VD-4338): reject a duplicate index before any SQL is built — two source_relations
     entries sharing an index would otherwise produce two identically-named CTEs (a SQL syntax
     error, not a clean failure) and there is no legitimate reason for a caller to repeat one. #}
  {% set seen_indexes = [] %}
  {% for src in source_relations %}
    {% if src.index in seen_indexes %}
      {{ exceptions.raise_compiler_error("vd_recon_materialize_keyed_mismatches: duplicate index in source_relations: " ~ src.index) }}
    {% endif %}
    {% do seen_indexes.append(src.index) %}
  {% endfor %}

  {# DC-29: a resolved source relation is re-validated unique on its own key here, defensively,
     rather than trusted from the caller — this is the actual enforcement point for "a non-unique
     source relation is never joined into the mismatch table," not a Negotiate-step-only guarantee.
     A relation missing key_columns, or found non-unique, is excluded and recorded as such (AC-93,
     AC-94); the macro call itself never fails because of it. Only key_columns[0] is used for the
     join, mirroring key_col = key_columns[0] above — a source relation is assumed single-column
     keyed even though the shape is an array for consistency with the pair's own key_columns. #}
  {% set joined_sources = [] %}
  {% set excluded_sources = [] %}
  {% for src in source_relations %}
    {% if not src.key_columns %}
      {% do excluded_sources.append({"relation": src.relation, "index": src.index, "reason": "no_key_columns"}) %}
    {% else %}
      {% set uniq = vd_recon_key_uniqueness(src.relation, [src.key_columns[0]]) %}
      {% if uniq.total != uniq.distinct or uniq.nulls > 0 %}
        {% do excluded_sources.append({"relation": src.relation, "index": src.index, "reason": "non_unique_key"}) %}
      {% else %}
        {% do joined_sources.append(src) %}
      {% endif %}
    {% endif %}
  {% endfor %}

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
         {% for src in joined_sources %},
         s{{ src.index }} as (select * from {{ src.relation }})
         {% endfor %}
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
           {% for src in joined_sources %}
           {% for col in src.columns %},
           s{{ src.index }}.{{ col }} as source_{{ src.index }}_{{ col }}
           {% endfor %}
           {% endfor %}
    from b
    full outer join t on b.{{ key_col }} = t.{{ key_col }}
    {% for src in joined_sources %}
    left join s{{ src.index }} on coalesce(b.{{ key_col }}, t.{{ key_col }}) = s{{ src.index }}.{{ src.key_columns[0] }}
    {% endfor %}
    where b.{{ key_col }} is null
       or t.{{ key_col }} is null
       or ({{ changed_condition }})
  {% endset %}
  {% do run_query(create_query) %}

  {% set count_query %}select count(*) as n from {{ mismatch_table }}{% endset %}
  {% set n = run_query(count_query).rows[0][0] %}

  {% set result = {"mismatch_table_ref": mismatch_table, "row_count": n, "source_relations_excluded": excluded_sources} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
