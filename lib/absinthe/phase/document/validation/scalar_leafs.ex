# [sic]
defmodule Absinthe.Phase.Document.Validation.ScalarLeafs do
  @moduledoc false

  # Validates that all leaf nodes are scalars.
  #
  # # Examples:
  # Assume `user` field is an object, and `email` is a scalar.
  #
  # ## DO NOT
  # ```
  # {
  #   user
  # }
  # ```
  #
  # ## DO
  # ```
  # {
  #   user {name email}
  # }
  # ```
  #
  # ## DO NOT
  # ```
  # {
  #   email { fields on scalar }
  # }
  # ```
  #
  # ## DO
  # ```
  # {
  #   email
  # }
  # ```

  alias Absinthe.{Blueprint, Phase, Type}

  use Absinthe.Phase
  use Absinthe.Phase.Validation

  @doc """
  Run the validation.
  """
  @spec run(Blueprint.t(), Keyword.t()) :: Phase.result_t()
  def run(input, _options \\ []) do
    result = Blueprint.prewalk(input, &handle_node(&1, input.schema))
    {:ok, result}
  end

  defp handle_node(%{schema_node: nil} = node, _schema), do: {:halt, node}

  defp handle_node(%Blueprint.Document.Field{schema_node: schema_node} = node, schema) do
    type = Type.expand(schema_node.type, schema)
    process(node, Type.unwrap(type), type)
  end

  defp handle_node(node, _) do
    node
  end

  @has_subfields [
    Type.Object,
    Type.Union,
    Type.Interface
  ]

  defp process(%{selections: []} = node, %unwrapped{}, type) when unwrapped in @has_subfields do
    bad_node(node, type, :missing_subfields)
  end

  defp process(%{selections: s} = node, %unwrapped{}, type)
       when s != [] and unwrapped not in @has_subfields do
    bad_node(node, type, :bad_subfields)
  end

  defp process(node, _, _) do
    node
  end

  defp bad_node(node, type, :bad_subfields = flag) do
    node
    |> flag_invalid(flag)
    |> put_error(error(node, no_subselection_allowed_message(node.name, Type.name(type))))
  end

  defp bad_node(node, type, :missing_subfields = flag) do
    node
    |> flag_invalid(flag)
    |> put_error(error(node, required_subselection_message(node.name, Type.name(type))))
  end

  # Generate the error
  @spec error(Blueprint.Document.Field.t(), String.t()) :: Phase.Error.t()
  defp error(node, message) do
    %Phase.Error{
      phase: __MODULE__,
      message: message,
      locations: [node.source_location]
    }
  end

  @doc """
  Generate the error message for an extraneous field subselection.
  """
  @spec no_subselection_allowed_message(String.t(), String.t()) :: String.t()
  def no_subselection_allowed_message(field_name, type_name) do
    ~s(Field "#{field_name}" must not have a selection since type "#{type_name}" has no subfields.)
  end

  @doc """
  Generate the error message for a missing field subselection.
  """
  @spec required_subselection_message(String.t(), String.t()) :: String.t()
  def required_subselection_message(field_name, type_name) do
    ~s(Field "#{field_name}" of type "#{type_name}" must have a selection of subfields. Did you mean "#{field_name} { ... }"?)
  end
end
