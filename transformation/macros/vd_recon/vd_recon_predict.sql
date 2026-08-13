{% macro vd_recon_predict(mismatch_table_ref, predicate, baseline_relation, column_pairs) %}
  {# DC-9/DC-10: predicate is a typed structure, never LLM-authored SQL text — see
     vd_recon_compile_predicate for the compiler that enforces this. PII status is resolved from
     the dbt graph via vd_recon_pii_columns, keyed off column_pairs' baseline_column — the same
     pairing convention vd_recon_materialize_keyless_mismatches and vd_recon_categorize_keyless
     already require and are already trusted for, so this introduces no new trust boundary. #}
  {% set pii_source_columns = vd_recon_pii_columns(baseline_relation) %}
  {% set mapped_columns = ['side', 'delta'] %}
  {% set pii_columns = [] %}
  {% for p in column_pairs %}
    {% do mapped_columns.append(p['target_column']) %}
    {% if p['baseline_column'] in pii_source_columns %}
      {% do pii_columns.append(p['target_column']) %}
    {% endif %}
  {% endfor %}

  {% set compiled = vd_recon_compile_predicate(predicate, mapped_columns, pii_columns, log_result=false) %}
  {% set compiled_query = vd_recon_compile_reproduction_query(mismatch_table_ref, compiled['sql'], log_result=false)['sql'] %}
  {% set n = run_query(compiled_query).rows[0][0] %}

  {% set result = {"matched_count": n, "predicate": predicate, "compiled_query": compiled_query} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
