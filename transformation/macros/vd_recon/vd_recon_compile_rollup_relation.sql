{% macro vd_recon_compile_rollup_relation(relation, group_by_columns, aggregate_column, mapped_columns, log_result=true) %}
  {# VD-4337, DC-27/28/29/30: the sanctioned way to align a detail-grain Target to the coarser
     common grain the comparison contract's "Different grain" mode already describes, without
     the LLM ever authoring roll-up SQL text. Every group-by column and the aggregate's source
     column must already be a mapped column (DC-27); the aggregate function is always sum — the
     design's "simple base-column aggregate," never an open function set (DC-28); no caller-
     supplied SQL string is accepted for any name (DC-29), mirroring DC-9's closure.

     The compiled subquery always also emits a synthetic grain_key column, since
     vd_recon_compare_keyed and vd_recon_materialize_keyed_mismatches (confirmed by reading their
     source) only ever use key_columns[0]: composite keys are not supported anywhere in the
     shipped macro set today. grain_key is built from LENGTH-PREFIXED segments, never a plain
     delimiter join — a plain '|'-join lets region='X|Y',month='Z' collide with
     region='X',month='Y|Z' into the identical string, which vd_recon_materialize_keyed_mismatches'
     plain `=` join would then silently treat as the same key (DC-30). Each segment instead
     declares its own exact length before its value, so no value's content can ever be mistaken
     for a segment boundary.

     Each segment also carries a leading presence flag ('N' for a NULL group-by value, 'V' for a
     real value) before its length prefix. Without it, coalesce(cast(col as varchar), '') maps
     both NULL and the literal empty string '' to the identical zero-length segment
     ('0000000000'), so a NULL-valued group and an empty-string-valued group would collide into
     the same grain_key even though they are distinct group-by tuples. The 'N'/'V' flag makes
     those two cases produce distinguishable segments ('N0000000000' vs 'V0000000000') while
     leaving every other case unchanged. #}
  {% if group_by_columns | length == 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: group_by_columns must not be empty") }}
  {% endif %}

  {% set identifier_re = '^[A-Za-z_][A-Za-z0-9_]*$' %}
  {% set group_by_quoted = [] %}
  {% for col in group_by_columns %}
    {% if col not in mapped_columns %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: group-by column '" ~ col ~ "' is not among the mapped columns") }}
    {% endif %}
    {% if not modules.re.match(identifier_re, col) %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: group-by column '" ~ col ~ "' is not a valid identifier") }}
    {% endif %}
    {% do group_by_quoted.append('"' ~ col ~ '"') %}
  {% endfor %}

  {% if aggregate_column is not mapping or 'source_column' not in aggregate_column or 'alias' not in aggregate_column %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: aggregate_column must be a mapping with 'source_column' and 'alias'") }}
  {% endif %}
  {% set source_column = aggregate_column['source_column'] %}
  {% set alias = aggregate_column['alias'] %}
  {% if source_column not in mapped_columns %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: aggregate source column '" ~ source_column ~ "' is not among the mapped columns") }}
  {% endif %}
  {% if not modules.re.match(identifier_re, source_column) or not modules.re.match(identifier_re, alias) %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: aggregate_column's source_column and alias must be valid identifiers") }}
  {% endif %}
  {% if alias == 'grain_key' %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: aggregate_column's alias may not be 'grain_key' — that name is reserved for the synthetic grain_key column this macro always emits") }}
  {% endif %}
  {% if alias in group_by_columns %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_rollup_relation: aggregate_column's alias '" ~ alias ~ "' collides with a group_by_columns name — the compiled subquery would emit duplicate column names") }}
  {% endif %}

  {% set grain_key_segments = [] %}
  {% for col in group_by_quoted %}
    {% set segment = "(case when " ~ col ~ " is null then 'N' else 'V' end) || lpad(cast(length(coalesce(cast(" ~ col ~ " as varchar), '')) as varchar), 10, '0') || coalesce(cast(" ~ col ~ " as varchar), '')" %}
    {% do grain_key_segments.append(segment) %}
  {% endfor %}
  {% set grain_key_expr = grain_key_segments | join(' || ') %}

  {% set sql %}(select {{ grain_key_expr }} as "grain_key", {{ group_by_quoted | join(', ') }}, sum("{{ source_column }}") as "{{ alias }}" from {{ relation }} group by {{ group_by_quoted | join(', ') }}) as vd_recon_rollup{% endset %}

  {% set result = {"sql": sql | trim} %}
  {% if log_result %}
    {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {% endif %}
  {{ return(result) }}
{% endmacro %}
