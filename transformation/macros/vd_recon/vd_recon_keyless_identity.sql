{% macro vd_recon_keyless_identity(column_pairs, side, pii_columns) %}
  {#- Identity is a TUPLE, not one digest: each non-PII column contributes its literal value and
      each PII-declared column contributes a hash of its OWN value. Hashing is a context-boundary
      control on what may cross into agent context, not a correctness requirement — grouping on a
      literal and grouping on a deterministic hash of it partition identically in-database.
      Combining columns into one whole-row digest would destroy the stage-3 localization the
      non-PII literals preserve.

      The per-column coalesce(..., chr(0)) is load-bearing and must not be removed: concat_ws
      SKIPS nulls, so without it (NULL,'a','b') and ('a','b',NULL) collapse to the same identity
      and a genuine difference reads as `aligned` — precisely the bag-collision the design
      forbids. chr(0) is used as the null sentinel because it cannot occur in a text value.

      One definition, called by both keyless macros, so their identities cannot drift apart. -#}
  {%- for p in column_pairs -%}
    {%- set col = p.baseline_column if side == 'baseline' else p.target_column -%}
    {%- if p.baseline_column in pii_columns -%}
      md5(coalesce(cast({{ col }} as varchar), chr(0)))
    {%- else -%}
      coalesce(cast({{ col }} as varchar), chr(0))
    {%- endif -%}
    {%- if not loop.last %}, {% endif -%}
  {%- endfor -%}
{% endmacro %}
