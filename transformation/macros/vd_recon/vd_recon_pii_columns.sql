{% macro vd_recon_pii_columns(relation) %}
  {# Resolves PII from the dbt graph rather than a caller argument, deliberately. If this were a
     parameter the LLM supplies, omitting it would silently disable every PII control in this
     macro set — the exact "trust the LLM with a fact" failure this whole layer exists to remove.
     The graph is built from schema.yml before any macro runs, so the declaration is authoritative
     and engine-agnostic (design: PII is declared in-repo, read before evidence is computed). #}
  {% set bare_name = relation.split('.') | last %}
  {% set pii = [] %}
  {% if execute %}
    {% for node in graph.nodes.values() %}
      {% if node.name == bare_name %}
        {% for col_name, col in node.columns.items() %}
          {% if col.meta is defined and col.meta.get('pii', false) %}
            {% do pii.append(col_name) %}
          {% endif %}
        {% endfor %}
      {% endif %}
    {% endfor %}
  {% endif %}
  {% set result = {"relation": relation, "pii_columns": pii | sort} %}
  {{ log("VD_RECON_RESULT " ~ tojson(result), info=True) }}
  {{ return(pii | sort) }}
{% endmacro %}
