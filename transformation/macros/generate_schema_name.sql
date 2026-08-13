{#-
  Use the model's configured schema verbatim rather than prefixing it with the
  target schema. Without this every layer lands as `main_core`, `main_finance`
  and so on, and the warehouse stops resembling the layer diagram in CONTEXT.md.
-#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
