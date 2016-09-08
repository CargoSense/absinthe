defmodule Absinthe.Phase.Document.Validation.UniqueInputFieldNames do
  @moduledoc """
  Validates document to ensure that all input fields have unique names.
  """

  alias Absinthe.{Blueprint, Phase}

  use Absinthe.Phase
  use Absinthe.Phase.Validation

  @doc """
  Run the validation.
  """
  @spec run(Blueprint.t) :: Phase.result_t
  def run(input) do
    result = Blueprint.prewalk(input, &handle_node/1)
    {:ok, result}
  end

  # Find input objects
  @spec handle_node(Blueprint.node_t) :: Blueprint.node_t
  defp handle_node(%Blueprint.Input.Object{} = node) do
    fields = Enum.map(node.fields, &(process(&1, node.fields)))
    %{node | fields: fields}
    |> inherit_invalid(fields, :duplicate_fields)
  end
  defp handle_node(node) do
    node
  end

  # Check an input field, finding any duplicates
  @spec process(Blueprint.Input.Field.t, [Blueprint.Input.Field.t]) :: Blueprint.Input.Field.t
  defp process(field, fields) do
    check_duplicates(field, Enum.filter(fields, &(&1.name == field.name)))
  end

  # Add flags and errors if necessary for each input field
  @spec check_duplicates(Blueprint.Input.Field.t, [Blueprint.Input.Field.t]) :: Blueprint.Input.Field.t
  defp check_duplicates(field, [_single]) do
    field
  end
  defp check_duplicates(field, _multiple) do
    %{
      field |
      flags: [:invalid, :duplicate_name] ++ field.flags,
      errors: [error(field) | field.errors]
    }
  end

  # Generate an error for an input field
  @spec error(Blueprint.Input.Field.t) :: Phase.t
  defp error(node) do
    Phase.Error.new(
      __MODULE__,
      error_message,
      node.source_location
    )
  end

  @doc """
  Generate the error message.
  """
  @spec error_message :: String.t
  def error_message do
    "Duplicate input field name."
  end

end
