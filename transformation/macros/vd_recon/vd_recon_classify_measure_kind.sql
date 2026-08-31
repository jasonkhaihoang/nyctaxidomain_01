{% macro vd_recon_classify_measure_kind(data_type) %}
  {# Non-associative-under-parallel-aggregation float types. DECIMAL/NUMERIC and integer types
     are exact fixed-point/exact-integer representations and are unaffected by VD-4398. #}
  {% set float_types = ['DOUBLE', 'FLOAT', 'REAL', 'FLOAT4', 'FLOAT8'] %}
  {% set normalized = data_type.upper().split('(')[0].strip() %}
  {% set measure_kind = 'float' if normalized in float_types else 'exact_numeric' %}
  {% set result = {"measure_kind": measure_kind} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
