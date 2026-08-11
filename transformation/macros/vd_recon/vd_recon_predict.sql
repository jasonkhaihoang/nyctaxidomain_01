{% macro vd_recon_predict(mismatch_table_ref, predicate) %}
  {# predicate is LLM-authored SQL boolean text (e.g. "order_status = 'partially_shipped'"),
     the design's own named residual risk (Open Question 1) — accepted, not structurally
     constrained here. Args are always passed via --args "$(cat <file>)"; never inline, since
     a predicate can contain an embedded single quote. #}
  {% set count_query %}
    select count(*) as n from {{ mismatch_table_ref }} where {{ predicate }}
  {% endset %}
  {% set n = run_query(count_query).rows[0][0] %}

  {% set result = {"matched_count": n, "predicate": predicate} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
