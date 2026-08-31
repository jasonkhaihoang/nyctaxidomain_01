{% macro vd_recon_relation_parts(relation) %}
  {# VD-4529: the single place in this macro set that removes adapter quoting from a relation
     reference. Relations reaching these macros may be adapter-quoted — they must be, on an
     ephemeral catalog whose name contains a hyphen, since an unquoted hyphenated identifier
     parses as subtraction. But information_schema and the dbt graph both store identifiers
     UNQUOTED, so every parse site needs the bare text.

     Quote EMISSION is delegated to the adapter (api.Relation.create); quote REMOVAL cannot be,
     because dbt exposes no inverse. Keeping that asymmetry contained in one macro is the point:
     no other vd_recon_* macro may strip a quote character. Only `"` is stripped — dbt-duckdb and
     dbt-fabric/dbt-sqlserver both quote with it, and this macro set is DuckDB-only today.

     Splitting on `.` assumes no identifier part contains a literal dot. Both materialize macros
     guard run_id against that (see their run_id validation), and catalog/schema come from the
     platform's own slug scheme, which is [A-Za-z0-9_-] only. #}
  {% set parts = [] %}
  {% for part in relation.split('.') %}
    {% do parts.append(part | replace('"', '') | trim) %}
  {% endfor %}
  {{ return(parts) }}
{% endmacro %}
