{#-
  Per-attendee schema routing for the workshop.

  dbt takes its schema from dbt_project.yml and profiles.yml, not from a SQL
  session variable - so the alias arrives as a dbt var instead:

      snow dbt execute ... DEFAQTO_SALESDB_DBT run --vars '{alias: kkothe}'

  That produces DBT_<ALIAS>_STAGING and DBT_<ALIAS>_MARTS, so six attendees can run
  the same deployed project without overwriting each other's models.

  On a missing alias this WARNS and routes to DBT_UNSET_* rather than raising.
  Raising was the first attempt and it broke `snow dbt deploy` outright, because
  deploy compiles the project and there is no alias at deploy time. A sentinel
  schema is the right compromise: deployment works, a run without the var is
  obvious both in the log and in the schema name, and nobody lands in another
  attendee's schema by accident.
-#}

{% macro generate_schema_name(custom_schema_name, node) -%}

    {%- set alias = var('alias', none) -%}

    {%- if alias is none or alias | trim == '' -%}
        {%- set alias = 'UNSET' -%}
        {%- do log(
            "No 'alias' var supplied - models will be written to DBT_UNSET_*. "
            ~ "Re-run with your own alias so your models land in your own schema: "
            ~ "--vars '{alias: your_initials}'", info=True) -%}
    {%- endif -%}

    {%- set base = target.schema -%}

    {%- if custom_schema_name is none -%}
        {#- a model with no +schema config still gets its own per-attendee schema -#}
        {{ (base ~ '_' ~ alias) | trim | upper }}
    {%- else -%}
        {{ (base ~ '_' ~ alias ~ '_' ~ custom_schema_name) | trim | upper }}
    {%- endif -%}

{%- endmacro %}
