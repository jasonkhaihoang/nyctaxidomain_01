{#-
  The trip natural key.

  `silver.trips` publishes `trip_key` as an md5 over the trip's natural
  columns. Bronze does not carry it, so any model reaching back to a
  fleet-specific bronze column has to recompute the identical expression --
  same column order, same separator -- or the join silently matches nothing.
  One macro, used on both sides, is the only way to keep them in step.
-#}
{% macro trip_natural_key(service_type, vendor, pickup, dropoff, pu, do, distance, total) -%}
    md5(concat_ws('|',
        {{ service_type }}, {{ vendor }}, {{ pickup }}, {{ dropoff }},
        {{ pu }}, {{ do }}, {{ distance }}, {{ total }}
    ))
{%- endmacro %}

{#- The three TLC airport zones. Note Newark: its service_zone is 'EWR', not
    'Airports', so a service_zone filter drops it. Encoded once, here. -#}
{% macro airport_zone_ids() -%}
    (1, 132, 138)
{%- endmacro %}

{% macro in_report_window(column) -%}
    {{ column }} >= timestamp '{{ var("report_start") }}'
    and {{ column }} < timestamp '{{ var("report_end") }}'
{%- endmacro %}
