{% macro vd_recon_aggregate_detail_evidence(relation, mismatch_table_ref, group_filter, candidate_expressions, mapped_columns, log_result=true) %}
  {# VD-4337, DC-31..DC-34: the sanctioned, aggregate-only way to inspect Target (or a relation
     the contract otherwise confirms) at a finer grain than the mismatch table holds. Never
     returns a literal detail row — every returned value is the result of sum() over the group.
     group_filter is restricted to a group the mismatch table has ALREADY localized as differing
     (DC-32(b)), and its columns must actually be carried into that table (DC-32(a)) — these are
     two distinguishable failures, not one, so a caller mistake never reads as a real "aligned"
     result. candidate_expressions reuse vd_recon_compile_column_expr's existing closed grammar
     unmodified (DC-33); that grammar already forbids a literal inside an arithmetic/transform
     expression, which is what makes the literal-rejection half of DC-33 true for free.

     vd_recon_schema_probe is NOT called here, even though it looks like the natural tool for the
     DC-32(a) precondition check: reading its source shows it only log()s its result and never
     calls return(), so it cannot be used as an internal Jinja function — calling it here would
     silently capture empty output, not a columns list. This macro inlines the identical
     information_schema query instead. #}
  {% if group_filter | length == 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: group_filter must not be empty") }}
  {% endif %}
  {% if candidate_expressions | length == 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: candidate_expressions must not be empty") }}
  {% endif %}

  {# DC-32(a): every group_filter key must already be carried into mismatch_table_ref as
     target_<column> — checked before anything else, via an inlined information_schema query
     (see the macro-level comment above for why vd_recon_schema_probe cannot be reused here). #}
  {% set ref_parts = mismatch_table_ref.split('.') %}
  {% set probe_query %}
    select column_name from information_schema.columns
    where table_catalog = '{{ ref_parts[0] }}' and table_schema = '{{ ref_parts[1] }}' and table_name = '{{ ref_parts[2] }}'
  {% endset %}
  {% set probed_columns = [] %}
  {% for row in run_query(probe_query).rows %}{% do probed_columns.append(row[0]) %}{% endfor %}
  {% for col in group_filter.keys() %}
    {% set prefixed = 'target_' ~ col %}
    {% if prefixed not in probed_columns %}
      {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: group_filter column '" ~ col ~ "' was never carried into " ~ mismatch_table_ref ~ " as '" ~ prefixed ~ "' — pass it as a carry_column or column_pair at materialize time before using it as a group_filter key") }}
    {% endif %}
  {% endfor %}

  {# One shared PII list, sourced once from relation's own PII declarations, used consistently
     for both the existence check (prefixed) and the evidence query (bare) — DC-34 requires this
     be one source of truth, never two independently-derived lists that could silently diverge. #}
  {% set pii_source_columns = vd_recon_pii_columns(relation) %}
  {% set filter_bare_columns = group_filter.keys() | list %}
  {% set filter_pii_bare = [] %}
  {% for col in filter_bare_columns %}{% if col in pii_source_columns %}{% do filter_pii_bare.append(col) %}{% endif %}{% endfor %}
  {% set filter_pii_prefixed = [] %}
  {% for col in filter_pii_bare %}{% do filter_pii_prefixed.append('target_' ~ col) %}{% endfor %}

  {# DC-32(b): the group_filter's columns, prefixed target_, must match an already-localized row. #}
  {% set existence_mapped = [] %}
  {% set existence_clauses = [] %}
  {% for col, value in group_filter.items() %}
    {% set prefixed = 'target_' ~ col %}
    {% do existence_mapped.append(prefixed) %}
    {% do existence_clauses.append({'op': '=', 'left': {'column': prefixed}, 'right': {'literal': value}}) %}
  {% endfor %}
  {% set existence_predicate = existence_clauses[0] if existence_clauses | length == 1 else {'op': 'and', 'clauses': existence_clauses} %}
  {% set existence_compiled = vd_recon_compile_predicate(existence_predicate, existence_mapped, filter_pii_prefixed, log_result=false) %}
  {% set existence_query %}select count(*) as n from {{ mismatch_table_ref }} where {{ existence_compiled['sql'] }}{% endset %}
  {% set existence_count = run_query(existence_query).rows[0][0] %}
  {% if existence_count == 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: group_filter " ~ group_filter ~ " does not match any row already localized as differing in " ~ mismatch_table_ref) }}
  {% endif %}

  {# The actual evidence query runs against relation directly, using relation-native (unprefixed)
     column names for both the WHERE filter and every candidate expression. Reuses filter_pii_bare
     computed above — never a second, independently-derived PII list. #}
  {% set filter_clauses = [] %}
  {% for col, value in group_filter.items() %}
    {% do filter_clauses.append({'op': '=', 'left': {'column': col}, 'right': {'literal': value}}) %}
  {% endfor %}
  {% set filter_predicate = filter_clauses[0] if filter_clauses | length == 1 else {'op': 'and', 'clauses': filter_clauses} %}
  {% set filter_compiled = vd_recon_compile_predicate(filter_predicate, mapped_columns, filter_pii_bare, log_result=false) %}

  {% set labels = [] %}
  {% set select_exprs = [] %}
  {% for entry in candidate_expressions %}
    {% if entry is not mapping or 'label' not in entry or 'expr' not in entry %}
      {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: each candidate_expressions entry must be a mapping with 'label' and 'expr'") }}
    {% endif %}
    {% if not modules.re.match('^[A-Za-z_][A-Za-z0-9_]*$', entry['label']) %}
      {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: candidate_expressions entry '" ~ entry['label'] ~ "' has a label that is not a valid identifier") }}
    {% endif %}
    {% if entry['label'] in labels %}
      {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: duplicate candidate_expressions label '" ~ entry['label'] ~ "'") }}
    {% endif %}
    {% do labels.append(entry['label']) %}
    {% set compiled_expr = vd_recon_compile_column_expr(entry['expr'], mapped_columns) %}
    {% for expr_col in compiled_expr['columns'] %}
      {% if expr_col in pii_source_columns %}
        {{ exceptions.raise_compiler_error("vd_recon_aggregate_detail_evidence: candidate_expressions entry '" ~ entry['label'] ~ "' may not reference a PII-declared column ('" ~ expr_col ~ "') — a single-row group would turn sum() into a raw-value read") }}
      {% endif %}
    {% endfor %}
    {% do select_exprs.append('sum(' ~ compiled_expr['sql'] ~ ') as "' ~ entry['label'] ~ '"') %}
  {% endfor %}

  {% set evidence_query %}select {{ select_exprs | join(', ') }} from {{ relation }} where {{ filter_compiled['sql'] }}{% endset %}
  {% set row = run_query(evidence_query).rows[0] %}
  {% set results = {} %}
  {% for label in labels %}
    {# DuckDB's Python client returns Decimal (not float) for some numeric column types/
       precisions when summed — tojson() below cannot serialize Decimal, so coerce here via
       Jinja's float filter. NULL is preserved as-is (a sum() over an empty/all-NULL group is a
       legitimate result) rather than being silently coerced to 0.0 by the float filter's default. #}
    {% set raw_value = row[loop.index0] %}
    {% do results.update({label: (raw_value | float) if raw_value is not none else none}) %}
  {% endfor %}

  {% set result = {"results": results} %}
  {% if log_result %}
    {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {% endif %}
  {{ return(result) }}
{% endmacro %}
