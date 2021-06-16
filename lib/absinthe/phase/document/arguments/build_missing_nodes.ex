defmodule Absinthe.Phase.Document.Arguments.BuildMissingNodes do
  @moduledoc false

  # Fills out missing arguments and input object fields.
  #
  # Filling out means inserting a stubbed `Input.Argument` or `Input.Field` struct.
  #
  # Only build those nodes when are non null and has no value or if a default. So
  # it can be used on `FillDefaults` and `FlagMissing` steps, respectively.

  use Absinthe.Phase
  alias Absinthe.{Blueprint, Type}

  @spec run(Blueprint.t(), Keyword.t()) :: {:ok, Blueprint.t()}
  def run(input, _options \\ []) do
    node = Blueprint.prewalk(input, &populate_node(&1, input.adapter, input.schema))
    {:ok, node}
  end

  defp populate_node(%{schema_node: nil} = node, _adapter, _schema), do: node

  defp populate_node(
         %{arguments: arguments, schema_node: %{args: schema_args}} = node,
         adapter,
         schema
       ) do
    arguments =
      fill_missing_nodes(
        Blueprint.Input.Argument,
        arguments,
        schema_args,
        node.source_location,
        adapter,
        schema
      )

    %{node | arguments: arguments}
  end

  defp populate_node(
         %Blueprint.Input.Object{fields: fields, schema_node: %{fields: schema_fields}} = node,
         adapter,
         schema
       ) do
    fields =
      fill_missing_nodes(
        Blueprint.Input.Field,
        fields,
        schema_fields,
        node.source_location,
        adapter,
        schema
      )

    %{node | fields: fields}
  end

  defp populate_node(
         %Blueprint.Input.Object{schema_node: %{of_type: type}} = node,
         adapter,
         schema
       ) do
    %{node | schema_node: type}
    |> populate_node(adapter, schema)
  end

  defp populate_node(node, _adapter, _schema), do: node

  defp fill_missing_nodes(type, arguments, schema_args, source_location, adapter, schema) do
    missing_schema_args = find_missing_schema_nodes(arguments, schema_args)

    missing_schema_args
    |> Map.values()
    |> Enum.reduce(arguments, fn
      # If it's deprecated without a default, ignore it
      %{deprecation: %{}, default_value: nil}, arguments ->
        arguments

      # If it has a default value, we want build it.
      %{default_value: val} = schema_node, arguments when not is_nil(val) ->
        arg = build_empty_node(type, schema_node, source_location, adapter, schema)
        [arg | arguments]

      # It isn't deprecated, it is null, and there's no default value. It's missing
      %{type: %Type.NonNull{}} = schema_node, arguments ->
        arg = build_empty_node(type, schema_node, source_location, adapter, schema)

        [arg | arguments]

      # No default value, and it's allowed to be null. Ignore it.
      _, arguments ->
        arguments
    end)
  end

  # Given the set of possible schema args, return only those not supplied in
  # the document argument / fields
  defp find_missing_schema_nodes(nodes, schema_nodes) do
    nodes
    |> Enum.filter(& &1.schema_node)
    |> Enum.reduce(schema_nodes, fn
      %{schema_node: %{identifier: id}}, acc ->
        Map.delete(acc, id)

      _, acc ->
        acc
    end)
  end

  defp build_empty_node(type, schema_node_arg, source_location, adapter, schema) do
    struct!(type, %{
      name: schema_node_arg.name |> build_name(adapter, type),
      input_value: %Blueprint.Input.Value{
        data: nil,
        normalized: nil,
        raw: nil,
        schema_node: Type.expand(schema_node_arg.type, schema)
      },
      schema_node: schema_node_arg,
      source_location: source_location
    })
  end

  defp build_name(name, adapter, Blueprint.Input.Argument) do
    adapter.to_external_name(name, :argument)
  end

  defp build_name(name, adapter, Blueprint.Input.Field) do
    adapter.to_external_name(name, :field)
  end
end
