defmodule Absinthe.Phase.Document.Arguments.FillDefaults do
  @moduledoc false

  # Fills out missing arguments and input object fields with default value.
  #
  # Filling out means inserting a stubbed `Input.Argument` or `Input.Field` struct.
  #
  # Only those default values which are non null are used to fill out.

  use Absinthe.Phase
  alias Absinthe.Blueprint

  @spec run(Blueprint.t(), Keyword.t()) :: {:ok, Blueprint.t()}
  def run(input, _options \\ []) do
    node = Blueprint.prewalk(input, &handle_node/1)
    {:ok, node}
  end

  defp handle_node(
         %Blueprint.Input.Argument{schema_node: schema_node, input_value: %{normalized: nil}} =
           node
       ) do
    handle_defaults(node, schema_node)
  end

  defp handle_node(
         %Blueprint.Input.Field{schema_node: schema_node, input_value: %{normalized: nil}} = node
       ) do
    handle_defaults(node, schema_node)
  end

  defp handle_node(node), do: node

  defp handle_defaults(%{input_value: input} = node, %{default_value: val})
       when not is_nil(val) do
    input = %{input | data: val, normalized: %Blueprint.Input.Generated{by: __MODULE__}}
    %{node | input_value: input}
  end

  defp handle_defaults(node, _), do: node
end
