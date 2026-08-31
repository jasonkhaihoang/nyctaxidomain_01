{% macro vd_recon_compile_predicate(predicate, mapped_columns, pii_columns, log_result=true) %}
  {# DC-9/DC-10: the only place any of the three predicate-accepting macros turn a caller
     argument into SQL text. Every operand and operator is validated against a closed grammar
     before it is ever concatenated, so there is no caller-supplied string this macro
     interpolates verbatim — the narrowing-oracle path SQL safety documents is closed
     structurally here, not by convention at each call site.

     `log_result` defaults to true so a standalone `dbt run-operation` call against this macro
     still surfaces its result via the VD_RECON_RESULT convention. A caller embedding this macro
     as an internal step (e.g. vd_recon_categorize_keyless) passes log_result=false, since
     otherwise the compiled SQL — which can carry a caller-supplied literal — would leak into
     that caller's own stdout ahead of its own VD_RECON_RESULT line, defeating the "no plaintext
     leaves the database" guarantee the outer macro is responsible for. #}
  {% set sql = vd_recon_compile_predicate_node(predicate, mapped_columns, pii_columns) %}
  {% set result = {"sql": sql} %}
  {% if log_result %}
    {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {% endif %}
  {{ return(result) }}
{% endmacro %}

{% macro vd_recon_compile_predicate_node(node, mapped_columns, pii_columns) %}
  {% if node is not mapping or 'op' not in node %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: predicate node must be a mapping with an 'op' key, got " ~ node) }}
  {% endif %}
  {% set op = node['op'] %}
  {% if op in ('and', 'or') %}
    {% if 'clauses' not in node or node['clauses'] | length < 2 %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: '" ~ op ~ "' requires a 'clauses' list of at least 2 predicates") }}
    {% endif %}
    {% set parts = [] %}
    {% for clause in node['clauses'] %}
      {% do parts.append(vd_recon_compile_predicate_node(clause, mapped_columns, pii_columns)) %}
    {% endfor %}
    {{ return('(' ~ parts | join(' ' ~ op ~ ' ') ~ ')') }}
  {% elif op in ('=', '!=', '<', '<=', '>', '>=') %}
    {% if 'left' not in node or 'right' not in node %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: '" ~ op ~ "' requires 'left' and 'right' operands") }}
    {% endif %}
    {% set left = vd_recon_compile_operand(node['left'], mapped_columns) %}
    {% set right = vd_recon_compile_operand(node['right'], mapped_columns) %}
    {% do vd_recon_check_pii_boundary(left, right, pii_columns) %}
    {{ return(left['sql'] ~ ' ' ~ op ~ ' ' ~ right['sql']) }}
  {% elif op == 'between' %}
    {% if 'operand' not in node or 'low' not in node or 'high' not in node %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: 'between' requires 'operand', 'low', and 'high'") }}
    {% endif %}
    {% set operand = vd_recon_compile_operand(node['operand'], mapped_columns) %}
    {% set low = vd_recon_compile_operand(node['low'], mapped_columns) %}
    {% set high = vd_recon_compile_operand(node['high'], mapped_columns) %}
    {% do vd_recon_check_pii_boundary(operand, low, pii_columns) %}
    {% do vd_recon_check_pii_boundary(operand, high, pii_columns) %}
    {{ return(operand['sql'] ~ ' between ' ~ low['sql'] ~ ' and ' ~ high['sql']) }}
  {% elif op in ('is null', 'is not null') %}
    {% if 'operand' not in node %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: '" ~ op ~ "' requires an 'operand'") }}
    {% endif %}
    {% set operand = vd_recon_compile_operand(node['operand'], mapped_columns) %}
    {{ return(operand['sql'] ~ ' ' ~ op) }}
  {% else %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: operator '" ~ op ~ "' is outside the closed operator set") }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_check_pii_boundary(a, b, pii_columns) %}
  {# DC-10: a literal may be compared only against a non-PII mapped column. Column-vs-column
     (even PII-vs-PII, e.g. baseline_email = target_email) is always allowed — only a
     literal opposite a PII column is the narrowing-oracle shape this rejects. This check is
     sound only because DC-9's grammar never lets a literal appear inside a ColumnExpr — see
     vd_recon_compile_column_expr's 'literal' branch. If that restriction is ever relaxed, this
     check must also inspect literals nested inside arithmetic, or DC-10 silently reopens. #}
  {% set a_pii = [] %}
  {% for c in a['columns'] %}{% if c in pii_columns %}{% do a_pii.append(c) %}{% endif %}{% endfor %}
  {% set b_pii = [] %}
  {% for c in b['columns'] %}{% if c in pii_columns %}{% do b_pii.append(c) %}{% endif %}{% endfor %}
  {% if a['is_literal'] and b_pii | length > 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: a literal may not be compared against PII-declared column(s) " ~ b_pii | join(', ')) }}
  {% endif %}
  {% if b['is_literal'] and a_pii | length > 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: a literal may not be compared against PII-declared column(s) " ~ a_pii | join(', ')) }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_compile_operand(operand, mapped_columns) %}
  {% if operand is not mapping %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: operand must be a mapping, got " ~ operand) }}
  {% endif %}
  {# DC-9: exactly one of these four keys — never two at once (e.g. both 'literal' and 'column'),
     which would let one validated key mask an unvalidated one sitting right next to it. #}
  {% set present_keys = [] %}
  {% for k in ['literal', 'column', 'op', 'transform'] %}
    {% if k in operand %}{% do present_keys.append(k) %}{% endif %}
  {% endfor %}
  {% if present_keys | length != 1 %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: operand must have exactly one of 'column', 'literal', 'op', or 'transform', got keys " ~ present_keys ~ " in " ~ operand) }}
  {% endif %}
  {% if 'literal' in operand %}
    {{ return({"sql": vd_recon_render_literal(operand['literal']), "columns": [], "is_literal": true}) }}
  {% else %}
    {% set expr = vd_recon_compile_column_expr(operand, mapped_columns) %}
    {{ return({"sql": expr['sql'], "columns": expr['columns'], "is_literal": false}) }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_compile_column_expr(expr, mapped_columns) %}
  {% if expr is not mapping %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: column expression must be a mapping, got " ~ expr) }}
  {% endif %}
  {% set present_keys = [] %}
  {% for k in ['literal', 'column', 'op', 'transform'] %}
    {% if k in expr %}{% do present_keys.append(k) %}{% endif %}
  {% endfor %}
  {% if present_keys | length != 1 %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: column expression must have exactly one of 'column', 'op', or 'transform' — a literal may not appear here, only as the direct operand of a comparison — got keys " ~ present_keys ~ " in " ~ expr) }}
  {% endif %}
  {% if 'literal' in expr %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: a literal may not appear inside an arithmetic or transform expression, only as the direct operand of a comparison") }}
  {% elif 'column' in expr %}
    {% set name = expr['column'] %}
    {% if name not in mapped_columns %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: column '" ~ name ~ "' is not among the mapped columns") }}
    {% endif %}
    {% if not modules.re.match('^[A-Za-z_][A-Za-z0-9_]*$', name) %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: column '" ~ name ~ "' is not a valid identifier") }}
    {% endif %}
    {{ return({"sql": '"' ~ name ~ '"', "columns": [name]}) }}
  {% elif 'op' in expr %}
    {# DC-9: exactly one level of arithmetic. left/right must be bare columns, never another
       arithmetic or transform node — matching the design doc's only worked example
       (abs(amount_target - amount_baseline)) and every real call site, with no speculative
       deeper nesting to verify or maintain. #}
    {% if expr['op'] not in ('+', '-', '*', '/') %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: arithmetic operator '" ~ expr['op'] ~ "' is outside the closed operator set") }}
    {% endif %}
    {% if 'left' not in expr or 'right' not in expr %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: arithmetic expression requires 'left' and 'right'") }}
    {% endif %}
    {% if expr['left'] is not mapping or 'column' not in expr['left'] or expr['left'] | length != 1
        or expr['right'] is not mapping or 'column' not in expr['right'] or expr['right'] | length != 1 %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: arithmetic 'left'/'right' must each be a bare {'column': ...} — one level of arithmetic only, no nested arithmetic or transform") }}
    {% endif %}
    {% set left = vd_recon_compile_column_expr(expr['left'], mapped_columns) %}
    {% set right = vd_recon_compile_column_expr(expr['right'], mapped_columns) %}
    {{ return({"sql": '(' ~ left['sql'] ~ ' ' ~ expr['op'] ~ ' ' ~ right['sql'] ~ ')', "columns": left['columns'] + right['columns']}) }}
  {% elif 'transform' in expr %}
    {{ return(vd_recon_compile_transform(expr, mapped_columns)) }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_compile_transform(expr, mapped_columns) %}
  {# arg may be a bare column or one arithmetic node (vd_recon_compile_column_expr enforces the
     one-level-of-arithmetic rule already) — never another transform, so transforms never stack. #}
  {% set transform = expr['transform'] %}
  {% if transform != 'coalesce' and (expr.get('arg') is not mapping or 'transform' in expr['arg']) %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: transform '" ~ transform ~ "' requires an 'arg' that is a column or one arithmetic expression — transforms may not wrap another transform") }}
  {% endif %}
  {% if transform == 'abs' %}
    {% set arg = vd_recon_compile_column_expr(expr['arg'], mapped_columns) %}
    {{ return({"sql": 'abs(' ~ arg['sql'] ~ ')', "columns": arg['columns']}) }}
  {% elif transform == 'round' %}
    {% set arg = vd_recon_compile_column_expr(expr['arg'], mapped_columns) %}
    {{ return({"sql": 'round(' ~ arg['sql'] ~ ')', "columns": arg['columns']}) }}
  {% elif transform == 'cast' %}
    {% set allowed_types = ['varchar', 'integer', 'double', 'date', 'timestamp'] %}
    {% if expr.get('type') not in allowed_types %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: cast type '" ~ expr.get('type') ~ "' is outside the closed type set " ~ allowed_types) }}
    {% endif %}
    {% set arg = vd_recon_compile_column_expr(expr['arg'], mapped_columns) %}
    {{ return({"sql": 'cast(' ~ arg['sql'] ~ ' as ' ~ expr['type'] ~ ')', "columns": arg['columns']}) }}
  {% elif transform == 'date_trunc' %}
    {% set allowed_parts = ['day', 'month', 'year'] %}
    {% if expr.get('part') not in allowed_parts %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: date_trunc part '" ~ expr.get('part') ~ "' is outside the closed part set " ~ allowed_parts) }}
    {% endif %}
    {% set arg = vd_recon_compile_column_expr(expr['arg'], mapped_columns) %}
    {{ return({"sql": "date_trunc('" ~ expr['part'] ~ "', " ~ arg['sql'] ~ ')', "columns": arg['columns']}) }}
  {% elif transform == 'coalesce' %}
    {% if 'args' not in expr or expr['args'] | length != 2 %}
      {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: coalesce requires an 'args' list of exactly 2 column expressions") }}
    {% endif %}
    {% set first = vd_recon_compile_column_expr(expr['args'][0], mapped_columns) %}
    {% set second = vd_recon_compile_column_expr(expr['args'][1], mapped_columns) %}
    {{ return({"sql": 'coalesce(' ~ first['sql'] ~ ', ' ~ second['sql'] ~ ')', "columns": first['columns'] + second['columns']}) }}
  {% else %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: transform '" ~ transform ~ "' is outside the closed transform set") }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_render_literal(value) %}
  {% if value is none %}
    {{ return('null') }}
  {% elif value is boolean %}
    {{ return('true' if value else 'false') }}
  {% elif value is number %}
    {{ return(value | string) }}
  {% elif value is string %}
    {{ return("'" ~ value | replace("'", "''") ~ "'") }}
  {% else %}
    {{ exceptions.raise_compiler_error("vd_recon_compile_predicate: literal must be a string, number, boolean, or null, got " ~ value) }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_predicate_columns(predicate, log_result=true) %}
  {# DC-13's column-containment half needs the column set a typed predicate reads, without
     compiling it to SQL or validating it against a mapped-columns allowlist — this macro is
     the read-only counterpart to vd_recon_compile_predicate_node, walking the identical
     grammar but collecting column names instead of assembling a SQL string. It performs no
     validation of its own; a malformed node still raises through the same
     exceptions.raise_compiler_error calls vd_recon_compile_predicate_node uses, since a
     predicate that cannot be compiled cannot have its columns meaningfully extracted either.

     Returns {"columns": list[str]} — a dict wrapping a sorted, deduplicated column-name list,
     never a bare list[str] — unwrap with ['columns'] before iterating, exactly as
     vd_recon_predict and vd_recon_validate_derived_operands both do below.

     `log_result` mirrors vd_recon_compile_predicate's own parameter of the same name and
     defaults to true for the same reason: a standalone `dbt run-operation` call against this
     macro still surfaces its result via the VD_RECON_RESULT convention. A caller embedding this
     macro as an internal step (vd_recon_predict, vd_recon_validate_derived_operands) passes
     log_result=false so this macro's own result never leaks ahead of that caller's own
     VD_RECON_RESULT line. #}
  {% set cols = vd_recon_predicate_columns_node(predicate) %}
  {% set unique_sorted = cols | unique | sort | list %}
  {% set result = {"columns": unique_sorted} %}
  {% if log_result %}
    {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {% endif %}
  {{ return(result) }}
{% endmacro %}

{% macro vd_recon_predicate_columns_node(node) %}
  {% if node is not mapping or 'op' not in node %}
    {{ exceptions.raise_compiler_error("vd_recon_predicate_columns: predicate node must be a mapping with an 'op' key, got " ~ node) }}
  {% endif %}
  {% set op = node['op'] %}
  {% set cols = [] %}
  {% if op in ('and', 'or') %}
    {% for clause in node['clauses'] %}
      {% do cols.extend(vd_recon_predicate_columns_node(clause)) %}
    {% endfor %}
  {% elif op in ('=', '!=', '<', '<=', '>', '>=') %}
    {% do cols.extend(vd_recon_operand_columns(node['left'])) %}
    {% do cols.extend(vd_recon_operand_columns(node['right'])) %}
  {% elif op == 'between' %}
    {% do cols.extend(vd_recon_operand_columns(node['operand'])) %}
    {% do cols.extend(vd_recon_operand_columns(node['low'])) %}
    {% do cols.extend(vd_recon_operand_columns(node['high'])) %}
  {% elif op in ('is null', 'is not null') %}
    {% do cols.extend(vd_recon_operand_columns(node['operand'])) %}
  {% else %}
    {{ exceptions.raise_compiler_error("vd_recon_predicate_columns: operator '" ~ op ~ "' is outside the closed operator set") }}
  {% endif %}
  {{ return(cols) }}
{% endmacro %}

{% macro vd_recon_operand_columns(operand) %}
  {# Mirrors vd_recon_compile_operand/vd_recon_compile_column_expr's traversal, minus the
     mapped-columns/PII validation those two enforce at compile time — this macro only
     collects names, so it never needs the allowlist those checks exist to guard. #}
  {% if operand is not mapping %}
    {{ exceptions.raise_compiler_error("vd_recon_predicate_columns: operand must be a mapping, got " ~ operand) }}
  {% endif %}
  {% if 'literal' in operand %}
    {{ return([]) }}
  {% elif 'column' in operand %}
    {{ return([operand['column']]) }}
  {% elif 'op' in operand %}
    {% set cols = [] %}
    {% do cols.extend(vd_recon_operand_columns(operand['left'])) %}
    {% do cols.extend(vd_recon_operand_columns(operand['right'])) %}
    {{ return(cols) }}
  {% elif 'transform' in operand %}
    {% set transform = operand['transform'] %}
    {% if transform == 'coalesce' %}
      {% set cols = [] %}
      {% for arg in operand['args'] %}
        {% do cols.extend(vd_recon_operand_columns(arg)) %}
      {% endfor %}
      {{ return(cols) }}
    {% else %}
      {{ return(vd_recon_operand_columns(operand['arg'])) }}
    {% endif %}
  {% else %}
    {{ exceptions.raise_compiler_error("vd_recon_predicate_columns: operand must have one of 'column', 'literal', 'op', or 'transform', got " ~ operand) }}
  {% endif %}
{% endmacro %}

{% macro vd_recon_validate_derived_operands(claim_predicate, baseline_columns, target_columns, source_relations=[]) %}
  {# DC-22 (VD-4316) plus DC-31/DC-32 (VD-4338): a derived_expression claim's operands must be
     recorded before the hypothesis is formed — in baseline_columns/target_columns, or, for a
     source-only operand, in the source_relations entry whose index that operand's own
     source_<n>_ prefix names. The pre-commitment TIMING rule is unchanged; only which fields
     it checks against widens (AC-96). An operand naming an index absent from source_relations
     is rejected exactly like any other unrecorded operand, never silently accepted. A column
     merely named source_<word> with no matching numeric-index prefix (e.g. an ordinary
     source_system column that happens to be baseline/target-mapped) must fall through to the
     baseline_columns/target_columns/all_columns check below, never be misrouted here — DC-30's
     duplicate-index rejection mirrors Task 3's, for the identical reason. #}
  {% set operands = vd_recon_predicate_columns(claim_predicate, log_result=false)['columns'] %}
  {% set all_columns = (baseline_columns + target_columns) | unique | list %}
  {% set source_columns_by_index = {} %}
  {% set seen_indexes = [] %}
  {% for src in source_relations %}
    {% if src.index in seen_indexes %}
      {{ exceptions.raise_compiler_error("vd_recon_validate_derived_operands: duplicate index in source_relations: " ~ src.index) }}
    {% endif %}
    {% do seen_indexes.append(src.index) %}
    {% do source_columns_by_index.update({src.index | string: src.columns}) %}
  {% endfor %}
  {% set unrecorded = [] %}
  {% for op_col in operands %}
    {% set source_match = modules.re.match('^source_([0-9]+)_(.+)$', op_col) %}
    {% if op_col.startswith('baseline_') %}
      {% set bare = op_col[9:] %}
      {% if bare not in baseline_columns %}{% do unrecorded.append(op_col) %}{% endif %}
    {% elif op_col.startswith('target_') %}
      {% set bare = op_col[7:] %}
      {% if bare not in target_columns %}{% do unrecorded.append(op_col) %}{% endif %}
    {% elif source_match %}
      {% set idx = source_match.group(1) %}
      {% set bare = source_match.group(2) %}
      {% if idx not in source_columns_by_index or bare not in source_columns_by_index[idx] %}
        {% do unrecorded.append(op_col) %}
      {% endif %}
    {% elif op_col not in all_columns %}
      {% do unrecorded.append(op_col) %}
    {% endif %}
  {% endfor %}
  {% if unrecorded | length > 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_validate_derived_operands: operand(s) not in the recorded column inventory: " ~ unrecorded | join(', ')) }}
  {% endif %}
  {% set result = {"valid": true, "columns": operands} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {{ return(result) }}
{% endmacro %}
