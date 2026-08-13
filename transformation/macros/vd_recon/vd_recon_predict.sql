{% macro vd_recon_predict(mismatch_table_ref, predicate, baseline_relation, column_pairs, claim_predicate=none) %}
  {# DC-9/DC-10: predicate is a typed structure, never LLM-authored SQL text — see
     vd_recon_compile_predicate for the compiler that enforces this. PII status is resolved from
     the dbt graph via vd_recon_pii_columns, keyed off column_pairs' baseline_column — the same
     pairing convention vd_recon_materialize_keyless_mismatches and vd_recon_categorize_keyless
     already require and are already trusted for, so this introduces no new trust boundary.

     DC-13 (VD-4316): claim_predicate is optional so every pre-existing eliminative/bare call
     (which backs no disposition on its own and has no claim to be scoped against) is unaffected.
     When supplied, scope_match is computed and returned; when omitted, scope_match is absent
     from the result entirely — never a null placeholder a caller could mistake for "checked and
     failed". #}
  {% set pii_source_columns = vd_recon_pii_columns(baseline_relation) %}
  {% set mapped_columns = ['side', 'delta'] %}
  {% set pii_columns = [] %}
  {# Pre-existing gap this task exposed: a keyless mismatch table (vd_recon_materialize_keyless_
     mismatches) carries each mapped column bare (its target_column name only), but a keyed one
     (vd_recon_materialize_keyed_mismatches) always carries it twice, prefixed baseline_<c>/
     target_<c> — the exact convention vd_recon_categorize_keyed's own keyed_mapped_columns
     already uses. Appending only the bare name left every keyed-table predicate unable to
     address either side under its natural column_pairs; every pre-existing keyed-table test
     routed around this by contriving a target_column equal to the prefixed name outright. The
     new DC-13..16 scope_match tests are the first callers to need natural column_pairs against a
     keyed table, so both prefixed forms are added here alongside the bare one — additive only:
     the bare name callers relied on (every keyless call site) is unchanged. #}
  {% for p in column_pairs %}
    {% do mapped_columns.append(p['target_column']) %}
    {% do mapped_columns.append('baseline_' ~ p['target_column']) %}
    {% do mapped_columns.append('target_' ~ p['target_column']) %}
    {% if p['baseline_column'] in pii_source_columns %}
      {% do pii_columns.append(p['target_column']) %}
      {% do pii_columns.append('baseline_' ~ p['target_column']) %}
      {% do pii_columns.append('target_' ~ p['target_column']) %}
    {% endif %}
  {% endfor %}

  {% set compiled = vd_recon_compile_predicate(predicate, mapped_columns, pii_columns, log_result=false) %}
  {% set compiled_query = vd_recon_compile_reproduction_query(mismatch_table_ref, compiled['sql'], log_result=false)['sql'] %}
  {% set n = run_query(compiled_query).rows[0][0] %}

  {% set result = {"matched_count": n, "predicate": predicate, "compiled_query": compiled_query} %}

  {% if claim_predicate is not none %}
    {# Column containment (DC-14): the test's column set must contain the claim's. Computed
       purely from the typed structure — no SQL involved — via vd_recon_predicate_columns.
       vd_recon_predicate_columns returns {"columns": list[str]}, not a bare list — unwrap with
       ['columns'] before iterating, or `for c in claim_columns` would iterate the dict's single
       key ('columns') instead of the actual column names. #}
    {% set claim_columns = vd_recon_predicate_columns(claim_predicate, log_result=false)['columns'] %}
    {% set test_columns = vd_recon_predicate_columns(predicate, log_result=false)['columns'] %}
    {% set missing_columns = [] %}
    {% for c in claim_columns %}
      {% if c not in test_columns %}{% do missing_columns.append(c) %}{% endif %}
    {% endfor %}
    {% set column_contains = (missing_columns | length == 0) %}

    {# Population containment (DC-15): every row the claim's predicate matches over the
       mismatch table must also match the test's predicate — claim_population MINUS
       test_population must be empty. Both predicates compile against the SAME mapped_columns/
       pii_columns the test itself used above, since claim_predicate names operands from the
       same confirmed mapping the test does. log_result=false: this is an internal population
       check, not the test's own reported result, and must not emit a second VD_RECON_RESULT
       line ahead of this macro's own.

       NULL-safe by construction (the defect VD-4316 was filed against): under SQL
       three-valued logic, `claim AND NOT test` evaluates to NULL — not TRUE, and therefore
       not counted by a bare `count(*) ... where ...` — whenever the test predicate is NULL on
       a row the claim predicate holds TRUE on. This is the ordinary case on a keyed mismatch
       table, where presence-class rows carry NULL baseline_*/target_* columns. A `count(*)
       where (claim) and not (test)` therefore silently drops exactly the rows this check
       exists to catch. Counting instead via `sum(case claim then 1 else 0) - sum(case claim
       and test then 1 else 0)` only ever evaluates `claim` and `claim and test` inside a CASE
       (which treats NULL as "no match", never "no count"), so a NULL test result on a
       claim-true row correctly leaves that row uncontained rather than silently excluded. #}
    {% set claim_compiled = vd_recon_compile_predicate(claim_predicate, mapped_columns, pii_columns, log_result=false) %}
    {% set containment_query %}
      select
        sum(case when ({{ claim_compiled['sql'] }}) then 1 else 0 end)
        - sum(case when ({{ claim_compiled['sql'] }}) and ({{ compiled['sql'] }}) then 1 else 0 end)
        as n
      from {{ mismatch_table_ref }}
    {% endset %}
    {% set uncontained_count = run_query(containment_query).rows[0][0] %}
    {% set population_contains = (uncontained_count == 0) %}

    {% do result.update({"scope_match": column_contains and population_contains}) %}
  {% endif %}

  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
