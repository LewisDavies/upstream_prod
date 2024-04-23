{% macro find_selected_nodes(parent_model, parent_project) %}
    {{ return(adapter.dispatch("find_selected_nodes", "upstream_prod")(parent_model, parent_project)) }}
{% endmacro %}

{% macro default__find_selected_nodes(parent_model, parent_project) %}
    /*******************
    Note on selection & tests

    The selected_resources variable is a list of all nodes to be executed on the current run.
    Below are some example elements:
    1. model.my_project.my_model
    2. snapshot.my_project.my_snapshot
    3. test.unique_my_model_id.<hash>

    In a nutshell, when ref() is called this package checks if the model is included in this 
    list and returns the appropriate relation. However, running a test (e.g. dbt test -s my_model) 
    only adds the test name (i.e. element 3) to selected_resources. The graph variable is used 
    to identify the models relied on by each test.

    Some tests rely on multiple models, such as relationship tests. For these, the package returns
    the dev relation for explicity selected models and tries to fetch prod relations for comparison
    models.
    
    Example: my_model has a relationship test against my_stg_model and dbt test -s my_model is run.
    As my_model was explicitly selected by the user, the dev relation is used as the base and is
    compared to the prod version of my_stg_model.
    *******************/

    -- Find models & snapshots selected for current run
    {% set selected = [] %}
    {% set selected_tests = [] %}
    {% for res in selected_resources %}
        {% if not res.startswith("test.") %}
            -- Get model name only when ref had only one arg
            {% if parent_project is none %}
                {% do selected.append(res.split(".")[2]) %}
            -- Get project.model when ref had two args
            {% else %}
                {% do selected.append(res.partition(".")[2]) %}
            {% endif %}
        {% else %}
            {% do selected_tests.append(res) %}
        {% endif %}
    {% endfor %}

    -- Find models being tested
    {% for test in selected_tests %}
        {% set test_node = graph.nodes[test] %}
        {% for test_ref in test_node.refs %}
            {% if test_ref.name == parent_model %}
                {% if parent_project is none %}
                    {% do selected.append(parent_model) %}
                {% elif test_ref.package == parent_project %}
                    {% do selected.append(parent_project ~ "." ~ parent_model) %}
                {% endif %}
            {% endif %}
        {% endfor %}
    {% endfor %}

    {{ return(set(selected)) }}

{% endmacro %}
