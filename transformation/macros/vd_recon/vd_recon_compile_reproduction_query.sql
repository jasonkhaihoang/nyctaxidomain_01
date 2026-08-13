{% macro vd_recon_compile_reproduction_query(mismatch_table_ref, predicate_sql, log_result=true) %}
  {# The one place the "select count(*) as n from <ref> where <sql>" wrapper shape is defined —
     vd_recon_predict, vd_recon_categorize_keyed, and vd_recon_categorize_keyless all call this
     rather than each hand-assembling the same string, so a future format change (e.g. adding a
     LIMIT) touches one file instead of three. #}
  {% set sql = "select count(*) as n from " ~ mismatch_table_ref ~ " where " ~ predicate_sql %}
  {% set result = {"sql": sql} %}
  {% if log_result %}
    {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {% endif %}
  {{ return(result) }}
{% endmacro %}
