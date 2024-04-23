{% macro ref(
    parent_arg_1,
    parent_arg_2=None, 
    prod_database=var("upstream_prod_database", None), 
    prod_schema=var("upstream_prod_schema", None),
    enabled=var("upstream_prod_enabled", True),
    fallback=var("upstream_prod_fallback", False),
    env_schemas=var("upstream_prod_env_schemas", False),
    version=None,
    prefer_recent=var("upstream_prod_prefer_recent", False),
    prod_database_replace=var("upstream_prod_database_replace", None)
) %}
    {{ return(adapter.dispatch("ref", "upstream_prod")(
        parent_arg_1, 
        parent_arg_2, 
        prod_database, 
        prod_schema, 
        enabled, 
        fallback, 
        env_schemas, 
        version, 
        prefer_recent, 
        prod_database_replace
    )) }}
{% endmacro %}

{% macro default__ref(
    parent_arg_1, 
    parent_arg_2, 
    prod_database, 
    prod_schema, 
    enabled, 
    fallback, 
    env_schemas, 
    version, 
    prefer_recent,
    prod_database_replace
) %}
    -- Handle two-argument refs
    -- TODO: update all usages of parent_model 
    -- TODO: check find_selected_nodes macro (how to pass project as well?)
    -- TODO: check find_model_node macro

    -- for packages, project name is the name of the package, e.g. model.facebook_ads.facebook_ads__account_report
    -- this means we can't simply use the user's project name when one isn't supplied
    -- instead, when only one arg (the model name) is supplied, we will match on just the model name, not project + model name

    {% if parent_arg_2 is none %}
        {% set parent_project = None %}
        {% set parent_model = parent_arg_1 %}
        {% set parent_ref = builtins.ref(parent_model, version=version) %}
    {% else %}
        {% set parent_project = parent_arg_1 %}
        {% set parent_model = parent_arg_2 %}
        {% set parent_ref = builtins.ref(parent_project, parent_model, version=version) %}
    {% endif %}
    {% set current_model = this.name if this is defined else "unknown model" %}

    -- Return builtin ref for ephemeral models, during parsing or when disabled
    {% if execute == false or enabled == false or parent_ref.is_cte
        or target.name in var("upstream_prod_disabled_targets", []) %}
        {{ return(parent_ref) }}
    {% endif %}

    -- Raise error if at least one required variable is not set
    {{ upstream_prod.check_reqd_vars(prod_database, prod_schema, env_schemas, prod_database_replace) }}

    {% set selected = upstream_prod.find_selected_nodes(parent_model, parent_project) %}
    -- Use dev relations for models being built during the current run
    {% if parent_model in selected %}
        {{ return(parent_ref) }}
    -- Try deferring to prod for non-selected upstream models
    {% else %}
        {% set parent_node = upstream_prod.find_model_node(parent_model, version) %}
        
        -- Set prod schema name
        {% if parent_node.resource_type == "snapshot" %}
            -- Snapshots use the same schema name regardless of the environment
            {% set parent_schema = parent_node.schema %}
        {% elif env_schemas == true %}
            {% set custom_schema_name = parent_node.config.schema %}
            {% set parent_schema = generate_schema_name(custom_schema_name, parent_node, True) | trim %}
        {% elif prod_schema is none %}
            -- No prod_schema = one-DB-per-env setup with same schema structure in all
            {% set parent_schema = parent_ref.schema %}
        {% else %}
            -- Schema structure is <env>[_<level>], e.g. prod, prod_stg or dev_int 
            {% set parent_schema = parent_ref.schema | replace(target.schema, prod_schema) %}
        {% endif %}

        -- Set prod database name
        {% if prod_database_replace is not none %}
            {% set parent_database = parent_ref.database.replace(prod_database_replace[0], prod_database_replace[1]) %}
        {% else %}
            {% set parent_database = prod_database or parent_ref.database %}
        {% endif %}

        -- Check whether the relations have been materialised in both envs
        /***************
        prod_rel_name helps the package find the correct prod relation for projects using a custom 
        generate_alias_name macro. It assumes that custom aliases are only used in dev envs and prod
        relations always have the same name as the model (+ version suffix when needed).
        It's hacky but it seems to work. 
        ***************/
        {% set re = modules.re %}
        {% set prod_rel_name = re.search("\w+(?=\.)", parent_node.path).group() %}
        {% set prod_rel = adapter.get_relation(parent_database, parent_schema, prod_rel_name) %}
        {% set dev_rel = load_relation(parent_ref) %}
        {% set prod_exists = prod_rel is not none %}
        {% set dev_exists = dev_rel is not none %}

        {% if prod_exists == true %}
            -- When option enabled, return the mostly recently updated of dev & prod relations
            {% if prefer_recent == true and dev_exists == true %}
                -- Find when dev & prod relations were last updated
                {% set dev_updated = upstream_prod.get_table_update_ts(dev_rel) %}
                {% set prod_updated = upstream_prod.get_table_update_ts(prod_rel) %}

                {% if dev_updated > prod_updated %}
                    {{ log("[" ~ current_model ~ "] " ~ parent_ref.table ~ " fresher in dev than prod, switching to dev relation", info=True) }}
                    {{ return(dev_rel) }}
                {% else %}
                    {{ return(prod_rel) }}
                {% endif %}
            {% else %}
                {{ return(prod_rel) }}
            {% endif %}
        {% elif dev_exists %}
            -- Return dev relation if prod doesn't exist & option is enabled
            {% if fallback == true %}
                {{ log("[" ~ current_model ~ "] " ~ parent_ref.table ~ " not found in prod, falling back to default target", info=True) }}
                {{ return(dev_rel) }}
            {% else %}
                {{ upstream_prod.raise_ref_not_found_error(current_model, parent_ref.database, parent_ref.schema, parent_ref.identifier) }}
            {% endif %}
        {% else %}
            {{ upstream_prod.raise_ref_not_found_error(current_model, parent_database, parent_schema, prod_rel_name) }}
        {% endif %}

    {% endif %}
{% endmacro %}
