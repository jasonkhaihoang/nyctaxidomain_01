{% macro vd_recon_outcome(mismatch_table_ref, key_column, units, tolerances, confirmed_hypotheses) %}
  {% set tol_by_col = {} %}
  {% for t in tolerances %}{% do tol_by_col.update({t.column: t}) %}{% endfor %}

  {% set confirmed_keys = [] %}
  {% for h in confirmed_hypotheses %}
    {% for u in h.claimed_units %}
      {% do confirmed_keys.append(u.key ~ '|' ~ (u.column if u.column is not none else '')) %}
    {% endfor %}
  {% endfor %}

  {% set material = [] %}
  {% set immaterial = [] %}
  {% for u in units %}
    {# A presence class or a one-sided null is always material: no arithmetic tolerance applies
       to an absent row or an absent value. Only a conflict between two present numbers can be
       within tolerance. #}
    {% if u.class != 'conflict' %}
      {% do material.append(u) %}
    {% else %}
      {% set tol = tol_by_col.get(u.column) %}
      {% if tol is none or tol.kind == 'exact' %}
        {% do material.append(u) %}
      {% else %}
        {% set delta_query %}
          select abs(cast(target_{{ u.column }} as double) - cast(baseline_{{ u.column }} as double)) as d,
                 nullif(abs(cast(baseline_{{ u.column }} as double)), 0) as base
          from {{ mismatch_table_ref }}
          where cast({{ key_column }} as varchar) = '{{ u.key | replace("'", "''") }}'
        {% endset %}
        {% set r = run_query(delta_query).rows[0] %}
        {% set ratio = (r[0] / r[1]) if r[1] is not none else none %}
        {% if tol.kind == 'fixed' and r[0] <= tol.threshold %}
          {% do immaterial.append(u) %}
        {% elif tol.kind == 'proportional' and ratio is not none and ratio <= tol.threshold %}
          {% do immaterial.append(u) %}
        {% else %}
          {% do material.append(u) %}
        {% endif %}
      {% endif %}
    {% endif %}
  {% endfor %}

  {% set material_confirmed = [] %}
  {% for u in material %}
    {% if (u.key ~ '|' ~ (u.column if u.column is not none else '')) in confirmed_keys %}
      {% do material_confirmed.append(u) %}
    {% endif %}
  {% endfor %}

  {# The four are exhaustive and mutually exclusive over the MATERIAL population's state alone. #}
  {% if material | length == 0 %}
    {% set outcome = 'aligned' %}
  {% elif material_confirmed | length == material | length %}
    {% set outcome = 'divergent-explained' %}
  {% elif material_confirmed | length > 0 %}
    {% set outcome = 'divergent-partial' %}
  {% else %}
    {% set outcome = 'divergent-unexplained' %}
  {% endif %}

  {% set result = {
    "outcome": outcome,
    "material_count": material | length,
    "immaterial_count": immaterial | length,
    "material_confirmed": material_confirmed | length
  } %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
