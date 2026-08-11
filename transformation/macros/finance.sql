{#-
  Fare arithmetic shared by every model that decomposes a trip total.
  Kept in one place because the component list changes whenever TLC adds a
  surcharge, and a model that misses one silently lands it in the residual.
-#}

{% macro surcharge_columns() -%}
    {{ return(['extra', 'mta_tax', 'improvement_surcharge', 'congestion_surcharge']) }}
{%- endmacro %}

{#- Sum of every pass-through the passenger pays that is not fare, tip or toll. -#}
{% macro total_surcharges(alias='t') -%}
    (
    {%- for c in surcharge_columns() %}
        coalesce({{ alias }}.{{ c }}, 0){{ ' + ' if not loop.last }}
    {%- endfor %}
    )
{%- endmacro %}

{#-
  What the total does not explain. A non-zero residual means either a component
  we do not model, or a total that was not derived from its parts.
-#}
{% macro fare_residual(alias='t') -%}
    (
        coalesce({{ alias }}.total_amount, 0)
        - coalesce({{ alias }}.fare_amount, 0)
        - coalesce({{ alias }}.tip_amount, 0)
        - coalesce({{ alias }}.tolls_amount, 0)
        - {{ total_surcharges(alias) }}
    )
{%- endmacro %}

{% macro safe_divide(numerator, denominator) -%}
    case when coalesce({{ denominator }}, 0) = 0 then null
         else {{ numerator }} / {{ denominator }} end
{%- endmacro %}
