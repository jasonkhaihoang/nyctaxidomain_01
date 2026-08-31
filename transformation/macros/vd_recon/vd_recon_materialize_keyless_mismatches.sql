{% macro vd_recon_materialize_keyless_mismatches(baseline_relation, target_relation, column_pairs, run_id) %}
  {# Nothing before this macro materializes WHICH keyless rows differ — vd_recon_compare_keyless
     (Task 5) only returns aggregate counts. This is that missing difference-unit table for the
     keyless path, mirroring what vd_recon_materialize_keyed_mismatches does for the keyed path.

     Identity is computed by the SHARED vd_recon_keyless_identity macro (Task 5), not reimplemented
     here: duplicating the coalesce/hash tuple logic across the two keyless macros is exactly the
     drift hazard that macro was extracted to eliminate (see its own docstring for the coalesce(...,
     chr(0)) null-sentinel rationale and the baseline_column-keyed PII check). pii_columns is
     resolved from the dbt graph here too, for the same reason vd_recon_compare_keyless does it:
     trusting a caller-supplied argument would silently disable PII hashing. #}
  {% set pii_columns = vd_recon_pii_columns(baseline_relation) %}
  {% set baseline_identity = vd_recon_keyless_identity(column_pairs, 'baseline', pii_columns) %}
  {% set target_identity = vd_recon_keyless_identity(column_pairs, 'target', pii_columns) %}

  {# VD-4529: same reasoning as the keyed macro — the adapter owns the quote character and its
     escaping rules, and quote_policy is explicit so a consumer project's `quoting:` config cannot
     silently reintroduce the bug. Never write a quote character here. #}
  {% if not run_id is string or not modules.re.match('^[A-Za-z0-9_]+$', run_id) %}
    {{ exceptions.raise_compiler_error("vd_recon_materialize_keyless_mismatches: run_id must match ^[A-Za-z0-9_]+$ — it becomes a quoted SQL identifier, and a '.' or '\"' inside it would silently corrupt the mismatch table's name and every downstream parse of it. Got: " ~ run_id) }}
  {% endif %}
  {% set mismatch_table = api.Relation.create(
       database=target.database,
       schema=target.schema,
       identifier='vd_recon_keyless_mismatch_' ~ run_id,
       quote_policy={'database': true, 'schema': true, 'identifier': true},
     ).render() %}

  {# Holds raw literal values, PII included, exactly as the keyed mismatch table does: predicates
     evaluate in-database and return only counts, so nothing here crosses into agent context.
     `identity` is the PII-hashed tuple and is the unit vd_recon_categorize_keyless buckets on.
     Every mapped column's literal survives under its TARGET-side name so a keyless hypothesis
     predicate (Task 7) can test a row's own literal values, not just its identity string. #}
  {% set create_query %}
    create table {{ mismatch_table }} as
    with b as (
      select concat_ws(chr(31), {{ baseline_identity }}) as identity
             {% for p in column_pairs %}, {{ p.baseline_column }} as {{ p.target_column }}{% endfor %}
      from {{ baseline_relation }}
    ),
    t as (
      select concat_ws(chr(31), {{ target_identity }}) as identity
             {% for p in column_pairs %}, {{ p.target_column }} as {{ p.target_column }}{% endfor %}
      from {{ target_relation }}
    ),
    b_counts as (select identity, count(*) as n from b group by identity),
    t_counts as (select identity, count(*) as n from t group by identity),
    deltas as (
      select coalesce(b_counts.identity, t_counts.identity) as identity,
             coalesce(b_counts.n, 0) - coalesce(t_counts.n, 0) as signed_delta
      from b_counts full outer join t_counts on b_counts.identity = t_counts.identity
    )
    select d.identity,
           case when d.signed_delta > 0 then 'missing_from_target' else 'additional_in_target' end as side,
           abs(d.signed_delta) as delta
           {% for p in column_pairs %}, src.{{ p.target_column }}{% endfor %}
    from deltas d
    join (select * from b union all select * from t) src on src.identity = d.identity
    where d.signed_delta <> 0
    qualify row_number() over (partition by d.identity, side order by 1) = 1
  {% endset %}
  {% do run_query(create_query) %}

  {% set count_query %}select count(*) as n from {{ mismatch_table }}{% endset %}
  {% set n = run_query(count_query).rows[0][0] %}
  {% set result = {"mismatch_table_ref": mismatch_table, "row_count": n} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
