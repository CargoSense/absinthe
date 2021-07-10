defmodule Absinthe.Phase.Document.Arguments.VariableTypesMatch do
  # Partially implements: 5.8.5. All Variable Usages are Allowed
  # Specifically, it implements "Variable usages must be compatible with the arguments they are passed to."
  # See relevant counter-example: https://spec.graphql.org/draft/#example-2028e

  use Absinthe.Phase

  alias Absinthe.Blueprint
  alias Absinthe.Blueprint.Document.{Operation, Fragment}

  def run(blueprint, _) do
    blueprint =
      blueprint
      |> check_operations()
      |> check_fragments()

    {:ok, blueprint}
  end

  def check_operations(%Blueprint{} = blueprint) do
    blueprint
    |> Map.update!(:operations, fn operations ->
      Enum.map(operations, &check_variable_types/1)
    end)
  end

  # A single fragment may be used by multiple operations.
  # Each operation may define its own variables.
  # This checks that each fragment is simultaneously consistent with the
  # variables defined in each of the operations which use that fragment.
  def check_fragments(%Blueprint{} = blueprint) do
    blueprint
    |> Map.update!(:fragments, fn fragments ->
      fragments
      |> Enum.map(fn fragment ->
        blueprint.operations
        |> Enum.filter(&Operation.uses?(&1, fragment))
        |> Enum.reduce(fragment, fn operation, fragment_acc ->
          check_variable_types(operation, fragment_acc)
        end)
      end)
    end)
  end

  def check_variable_types(%Operation{} = op) do
    variable_defs = Map.new(op.variable_definitions, &{&1.name, &1})
    Blueprint.prewalk(op, &check_var_type(&1, op.name, variable_defs))
  end

  def check_variable_types(%Operation{} = op, %Fragment.Named{} = fragment) do
    variable_defs = Map.new(op.variable_definitions, &{&1.name, &1})
    Blueprint.prewalk(fragment, &check_var_type(&1, op.name, variable_defs))
  end

  defp check_var_type(%{schema_node: nil} = node, _, _) do
    {:halt, node}
  end

  defp check_var_type(
         %Blueprint.Input.Value{
           raw: %{content: %Blueprint.Input.Variable{} = var},
           schema_node: schema_node
         } = node,
         op_name,
         variable_defs
       ) do
    case Map.fetch(variable_defs, var.name) do
      {:ok, %{schema_node: var_schema_type}} ->
        # null vs not null is handled elsewhere
        var_schema_type = Absinthe.Type.unwrap(var_schema_type)
        arg_schema_type = Absinthe.Type.unwrap(schema_node)

        if var_schema_type && arg_schema_type && var_schema_type.name != arg_schema_type.name do
          # error
          var_with_error =
            put_error(var, %Absinthe.Phase.Error{
              phase: __MODULE__,
              message: error_message(op_name, var, var_schema_type.name, arg_schema_type.name),
              locations: [var.source_location]
            })

          {:halt, put_in(node.raw.content, var_with_error)}
        else
          node
        end

      _ ->
        node
    end
  end

  defp check_var_type(node, _, _) do
    node
  end

  def error_message(op, variable, var_type, arg_type) do
    start =
      case op || "" do
        "" -> "Variable"
        op -> "In operation `#{op}, variable"
      end

    "#{start} `#{Blueprint.Input.inspect(variable)}` of type `#{var_type}` found as input to argument of type `#{arg_type}`."
  end
end
