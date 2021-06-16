defmodule Absinthe.Phase.Document.Arguments.FlagMissing do
  @moduledoc false

  # Fills out missing arguments and input object fields.
  #
  # If an argument or input object field is non null and missing, it is marked as missing

  use Absinthe.Phase
  alias Absinthe.{Blueprint, Type}

  @spec run(Blueprint.t(), Keyword.t()) :: {:ok, Blueprint.t()}
  def run(input, _options \\ []) do
    node = Blueprint.prewalk(input, &handle_node/1)
    {:ok, node}
  end

  defp handle_node(
         %Blueprint.Input.Argument{schema_node: schema_node, input_value: %{normalized: nil}} =
           node
       ) do
    flag_missing(node, schema_node)
  end

  defp handle_node(
         %Blueprint.Input.Field{schema_node: schema_node, input_value: %{normalized: nil}} = node
       ) do
    flag_missing(node, schema_node)
  end

  defp handle_node(node), do: node

  # NOTE: find regression or remove dead code
  # defp flag_missing(node, %{deprecation: %{}}), do: node

  defp flag_missing(node, %{type: %Type.NonNull{}}), do: node |> flag_invalid(:missing)
  defp flag_missing(node, _), do: node
end
