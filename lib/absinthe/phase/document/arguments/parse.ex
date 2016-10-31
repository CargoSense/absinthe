defmodule Absinthe.Phase.Document.Arguments.Parse do

  @moduledoc false

  # Parses Leaf Node inputs

  alias Absinthe.Blueprint.Input
  alias Absinthe.{Blueprint, Type}
  use Absinthe.Phase

  def run(input, _options \\ []) do
    result = Blueprint.prewalk(input, &handle_node/1)
    {:ok, result}
  end

  defp handle_node(%{schema_node: nil} = node) do
    {:halt, node}
  end
  defp handle_node(%{normalized: nil} = node) do
    node
  end
  defp handle_node(%Input.Value{normalized: normalized} = node) do
    case build_value(normalized, node.schema_node) do
      {:ok, value} ->
        %{node | data: value}
      :not_leaf_node ->
        node
      {:error, flag} ->
        %{node | normalized: normalized |> flag_invalid(flag)}
    end
  end
  defp handle_node(node), do: node

  defp build_value(normalized, %Type.Scalar{} = schema_node) do
    case Type.Scalar.parse(schema_node, normalized) do
      :error ->
        {:error, :bad_parse}
      {:ok, val} ->
        {:ok, val}
    end
  end
  defp build_value(normalized, %Type.Enum{} = schema_node) do
    case Type.Enum.parse(schema_node, normalized) do
      {:ok, %{value: value}} ->
        {:ok, value}
      :error ->
        {:error, :bad_parse}
    end
  end
  defp build_value(normalized, %Type.NonNull{of_type: inner_type}) do
    build_value(normalized, inner_type)
  end
  defp build_value(_, _) do
    :not_leaf_node
  end
end
