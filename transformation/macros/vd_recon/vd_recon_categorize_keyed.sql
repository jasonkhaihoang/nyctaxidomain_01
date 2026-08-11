{% macro vd_recon_categorize_keyed(mismatch_table_ref, key_column, baseline_relation, column_names, predicates) %}
  {# DC-8: a PII key would put a literal PII value into this macro's own JSON log line, which
     crosses the context boundary ADR-0004 governs. There is no safe degradation here — reject
     and let the contract pick a non-PII surrogate key or keyless mode. PII is resolved from the
     dbt graph, never from a caller argument, so the LLM cannot disable this by omission. #}
  {% set pii_columns = vd_recon_pii_columns(baseline_relation) %}
  {% if key_column in pii_columns %}
    {{ exceptions.raise_compiler_error("vd_recon_categorize_keyed: key column '" ~ key_column ~ "' is PII-declared; its literal values would cross into agent context. Confirm a non-PII surrogate key, or use keyless mode.") }}
  {% endif %}

  {% set seen_ids = [] %}
  {% for p in predicates %}
    {% if not modules.re.match('^[A-Za-z0-9_]+$', p.hypothesis_id) %}
      {{ exceptions.raise_compiler_error("vd_recon_categorize_keyed: hypothesis_id '" ~ p.hypothesis_id ~ "' does not match ^[A-Za-z0-9_]+$") }}
    {% endif %}
    {# Two entries sharing an id would tally as count(distinct hypothesis_id) = 1, so a genuine
       overlap between them would read as a single clean claim — silently defeating DC-1. #}
    {% if p.hypothesis_id in seen_ids %}
      {{ exceptions.raise_compiler_error("vd_recon_categorize_keyed: duplicate hypothesis_id '" ~ p.hypothesis_id ~ "'; each hypothesis claims its own set") }}
    {% endif %}
    {% do seen_ids.append(p.hypothesis_id) %}
    {% if p.column not in column_names %}
      {{ exceptions.raise_compiler_error("vd_recon_categorize_keyed: predicate column '" ~ p.column ~ "' is not among the contract's mapped columns") }}
    {% endif %}
  {% endfor %}

  {# A null key cannot be bucketed: it never satisfies an equijoin, so a claimed cell would
     silently fall through to `unexplained`. vd_recon_compare_keyed already surfaces this as
     invalid_key_alignment; refuse rather than mis-attribute. #}
  {% set null_key_check %}select count(*) as n from {{ mismatch_table_ref }} where {{ key_column }} is null{% endset %}
  {% if run_query(null_key_check).rows[0][0] > 0 %}
    {{ exceptions.raise_compiler_error("vd_recon_categorize_keyed: mismatch table contains a null " ~ key_column ~ "; resolve invalid key alignment before attributing") }}
  {% endif %}

  {# The measured difference is NOT "every column where the two sides differ". A key present on
     one side only is ONE presence unit, not one spurious cell per mapped column — the design's
     difference-unit table defines the keyed unit's measured value as "a value delta, OR a
     presence class for a key found on only one side". Conflating them would both inflate the
     unit count and erase the conflict / one-sided-null split that drives different stage-4
     hypotheses.

     Bucketing happens in Jinja on a tally, never in SQL via a WHEN/THEN chain — an ordered CASE
     is exactly the first-match-wins assignment DC-1 forbids. n_hyp is returned rather than a
     sentinel bucket string because a caller-supplied hypothesis_id could collide with the
     sentinel (the id regex permits underscores). #}
  {% set bucket_query %}
    with presence_units as (
      select distinct
             cast({{ key_column }} as varchar) as unit_key,
             cast(null as varchar) as unit_column,
             case when not target_present then 'missing_from_target'
                  else 'additional_in_target' end as unit_class
      from {{ mismatch_table_ref }}
      where not baseline_present or not target_present
    ),
    value_units as (
      {% for col in column_names %}
      select distinct
             cast({{ key_column }} as varchar) as unit_key,
             '{{ col }}' as unit_column,
             case when baseline_{{ col }} is null or target_{{ col }} is null
                  then 'one_sided_null' else 'conflict' end as unit_class
      from {{ mismatch_table_ref }}
      where baseline_present and target_present
        and baseline_{{ col }} is distinct from target_{{ col }}
      {% if not loop.last %}union all{% endif %}
      {% endfor %}
    ),
    all_units as (
      select * from presence_units union all select * from value_units
    ),
    claims as (
      {% if predicates | length > 0 %}
      {% for p in predicates %}
      select distinct
             cast({{ key_column }} as varchar) as unit_key,
             '{{ p.column }}' as unit_column,
             '{{ p.hypothesis_id }}' as hypothesis_id
      from {{ mismatch_table_ref }}
      where baseline_present and target_present
        and baseline_{{ p.column }} is distinct from target_{{ p.column }}
        and ({{ p.predicate }})
      {% if not loop.last %}union all{% endif %}
      {% endfor %}
      {% else %}
      select cast(null as varchar) as unit_key, cast(null as varchar) as unit_column,
             cast(null as varchar) as hypothesis_id
      from {{ mismatch_table_ref }} where false
      {% endif %}
    ),
    tallied as (
      select unit_key, unit_column,
             count(distinct hypothesis_id) as n_hyp,
             min(hypothesis_id) as sole_hypothesis
      from claims
      group by unit_key, unit_column
    )
    select a.unit_key, a.unit_column, a.unit_class,
           coalesce(t.n_hyp, 0) as n_hyp,
           t.sole_hypothesis
    from all_units a
    left join tallied t
      on a.unit_key = t.unit_key
     and a.unit_column is not distinct from t.unit_column
    order by a.unit_key, a.unit_column
  {% endset %}
  {% set rows = run_query(bucket_query).rows %}

  {% set claimed = {} %}
  {% for p in predicates %}
    {% do claimed.update({p.hypothesis_id: []}) %}
  {% endfor %}
  {% set residual = [] %}
  {% set unexplained = [] %}

  {% for row in rows %}
    {% set unit = {"key": row[0], "column": row[1], "class": row[2]} %}
    {% if row[3] == 0 %}
      {% do unexplained.append(unit) %}
    {% elif row[3] > 1 %}
      {% do residual.append(unit) %}
    {% else %}
      {% do claimed[row[4]].append(unit) %}
    {% endif %}
  {% endfor %}

  {% set result = {"claimed": claimed, "residual": residual, "unexplained": unexplained} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
{% endmacro %}
