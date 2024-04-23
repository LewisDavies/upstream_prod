{% macro find_model_node(model, project, version) %}
    {{ return(adapter.dispatch("find_model_node", "upstream_prod")(model, project, version)) }}
{% endmacro %}

{% macro default__find_model_node(model, project, version) %}

    {% if execute == true %}
        {% set matching_nodes = [] %}
        {% for n in graph.nodes.values() if n["name"] == model %}
            {% if project is none or project == n["package_name"] %}
                {% if version is not none %}
                    {% if n["version"] == version %}
                        {% do matching_nodes.append(n) %}
                    {% endif %}
                {% else %}
                    {% if n["version"] == n["latest_version"] %}
                        {% do matching_nodes.append(n) %}
                    {% endif %}
                {% endif %}
            {% endif %}
        {% endfor %}
        {{ return(matching_nodes | first) }}
    {% endif %}

{% endmacro %}
