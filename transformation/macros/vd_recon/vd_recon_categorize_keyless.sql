{% macro vd_recon_categorize_keyless(mismatch_table_ref, predicates) %}
  {% for p in predicates %}
    {% if not modules.re.match('^[A-Za-z0-9_]+$', p.hypothesis_id) %}
      {{ exceptions.raise_compiler_error("vd_recon_categorize_keyless: hypothesis_id '" ~ p.hypothesis_id ~ "' does not match ^[A-Za-z0-9_]+$") }}
    {% endif %}
  {% endfor %}

  {% set seen_ids = [] %}
  {% for p in predicates %}
    {% if p.hypothesis_id in seen_ids %}
      {{ exceptions.raise_compiler_error("vd_recon_categorize_keyless: duplicate hypothesis_id '" ~ p.hypothesis_id ~ "'") }}
    {% endif %}
    {% do seen_ids.append(p.hypothesis_id) %}
  {% endfor %}

  {# No `column` argument, unlike the keyed macro: keyless mode has no baseline/target row pairing,
     so a predicate tests the row's own values rather than a per-column difference. Only
     presence-oriented mechanisms (filter, join, omitted union) are testable here.

     unit_id is an OPAQUE digest of the identity tuple, never the tuple itself. The tuple is a
     concat_ws of every mapped column, so returning it verbatim would be a row-body projection —
     which the design excludes "on PII and non-PII columns alike, since they launder row content
     through an aggregate's return shape." The plaintext tuple stays in-database, where predicates
     still evaluate against it and only counts cross out.

     `delta` is carried into the unit because the design defines the keyless difference unit as a
     row tuple WITH its multiplicity delta. Dropping it would make an identity with delta 5
     indistinguishable from one with delta 1, and would break DC-6's union invariant against
     vd_recon_compare_keyless, which sums multiplicities. #}
  {% set bucket_query %}
    with all_units as (
      select identity, side, delta from {{ mismatch_table_ref }}
    ),
    claims as (
      {% if predicates | length > 0 %}
      {% for p in predicates %}
      select identity, side, '{{ p.hypothesis_id }}' as hypothesis_id
      from {{ mismatch_table_ref }}
      where ({{ p.predicate }})
      {% if not loop.last %}union all{% endif %}
      {% endfor %}
      {% else %}
      select cast(null as varchar) as identity, cast(null as varchar) as side,
             cast(null as varchar) as hypothesis_id
      from {{ mismatch_table_ref }} where false
      {% endif %}
    ),
    tallied as (
      select identity, side,
             count(distinct hypothesis_id) as n_hyp,
             min(hypothesis_id) as sole_hypothesis
      from claims group by identity, side
    )
    select md5(a.identity) as unit_id, a.side, a.delta,
           coalesce(t.n_hyp, 0) as n_hyp, t.sole_hypothesis
    from all_units a
    left join tallied t on a.identity = t.identity and a.side = t.side
    order by a.identity, a.side
  {% endset %}
  {% set rows = run_query(bucket_query).rows %}

  {% set claimed = {} %}
  {% for p in predicates %}{% do claimed.update({p.hypothesis_id: []}) %}{% endfor %}
  {% set residual = [] %}
  {% set unexplained = [] %}

  {% for row in rows %}
    {% set unit = {"unit_id": row[0], "side": row[1], "delta": row[2]} %}
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
