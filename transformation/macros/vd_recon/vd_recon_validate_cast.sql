{% macro vd_recon_extract_expression_operands(expression) %}
  {# Internal helper: extracts the column-reference/operand set a raw SQL expression string
     reads, by regex tokenization — never by executing, planning, or parsing the expression
     through a SQL engine. This is a deliberately different extraction strategy from
     vd_recon_predicate_columns/vd_recon_compile_column_expr, which walk this skill's own closed
     typed-predicate grammar (DC-9, DC-10): a proposed cast expression and a baseline's compiled
     expression (read verbatim, as opaque text, from a dbt manifest per
     references/plan-negotiation.md's "Compiled-expression handling" section) are both raw SQL
     text with no typed structure behind them, so there is no typed grammar to walk here.

     Tokenization: first strip single-quoted string literals (so a literal like 'foo' never
     reads as an operand named foo), then split on any run of non-identifier/non-dot characters,
     keep tokens matching a plain or dot-qualified SQL identifier
     (`[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*`, e.g. `t.amount`), drop any token
     immediately followed by an opening parenthesis (a function call, e.g. `cast(`, `round(`,
     `abs(` — a function name is never an operand, including a schema-qualified one like
     `main.round(`), and drop any token whose final dot-segment is in the closed SQL-keyword/
     type-name denylist below (case-insensitive) or that parses as a bare numeric literal. A
     dot-qualified reference is normalized to its final segment (`t.amount` -> `amount`) so an
     alias/table-qualified operand compares equal to its unqualified form elsewhere in the same
     check. What remains is the column-reference set. #}
  {% set denylist = [
    'cast', 'as', 'is', 'not', 'null', 'and', 'or', 'when', 'then', 'else', 'end', 'case',
    'true', 'false', 'distinct', 'over', 'partition', 'by', 'asc', 'desc',
    'int', 'integer', 'bigint', 'smallint', 'tinyint', 'float', 'float4', 'float8', 'double',
    'real', 'decimal', 'numeric', 'varchar', 'char', 'text', 'string', 'boolean', 'bool',
    'date', 'timestamp', 'time', 'interval', 'blob', 'uuid', 'json', 'hugeint'
  ] %}
  {% set stripped_expression = modules.re.sub("'[^']*'", ' ', expression) %}
  {% set raw_tokens = modules.re.findall('[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*|\(|[0-9]+', stripped_expression) %}
  {% set operands = [] %}
  {% for i in range(raw_tokens | length) %}
    {% set tok = raw_tokens[i] %}
    {% set is_identifier = modules.re.match('^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*$', tok) %}
    {% if is_identifier %}
      {% set next_tok = raw_tokens[i + 1] if (i + 1) < (raw_tokens | length) else none %}
      {% set is_function_call = (next_tok == '(') %}
      {% set operand_name = tok.split('.') | last %}
      {% if not is_function_call and operand_name.lower() not in denylist and operand_name not in operands %}
        {% do operands.append(operand_name) %}
      {% endif %}
    {% endif %}
  {% endfor %}
  {{ return(operands | sort) }}
{% endmacro %}

{% macro vd_recon_validate_cast(cast_expression, baseline_expression) %}
  {# AC-100/AC-101 (VD-4527): the mechanical, macro-computed cast-operand check — never a
     free-text or self-reported justification field, per ADR-0014's precedent for
     vd_recon_predict/scope_match. A proposed cast's expression is rejected only when it reads
     an operand the baseline's own compiled expression for that column never reads; a scalar
     transform of the same operand set the baseline already reads (a unit conversion, rounding,
     widening) is unaffected, since it introduces no new operand.

     DC-33 (forbidden state): the caller must never apply a cast this macro flags
     operand_mismatch: true — this macro only computes the verdict, it does not itself gate
     application; that gate lives in the Negotiate-step and replay logic that calls it
     (references/plan-negotiation.md).

     DC-34 (required output): on rejection, the caller replaces the cast with the
     baseline-faithful mapping — the identity/rename mapping that adds no operand beyond
     baseline_expression — never an invented or unvalidated mapping; this macro does not
     construct that replacement mapping itself, since the baseline-faithful mapping is always
     just baseline_expression's own operand set with no cast at all.

     Deterministic and side-effect-free: re-running this macro against the same two expressions
     (as AC-101 requires on every contract load/replay) always reproduces the same verdict,
     since it is a pure function of its two string arguments. #}
  {% set cast_operands = vd_recon_extract_expression_operands(cast_expression) %}
  {% set baseline_operands = vd_recon_extract_expression_operands(baseline_expression) %}
  {% set extra_operands = [] %}
  {% for op in cast_operands %}
    {% if op not in baseline_operands %}{% do extra_operands.append(op) %}{% endif %}
  {% endfor %}
  {% set result = {"operand_mismatch": (extra_operands | length > 0), "extra_operands": extra_operands} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {{ return(result) }}
{% endmacro %}
