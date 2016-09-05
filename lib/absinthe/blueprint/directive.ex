defmodule Absinthe.Blueprint.Directive do

  alias Absinthe.{Blueprint, Phase}

  @enforce_keys [:name]
  defstruct [
    :name,
    arguments: [],
    # When part of a Document
    source_location: nil,
    # Added by phases
    schema_node: nil,
    flags: [],
    errors: [],
  ]

  @type t :: %__MODULE__{
    name: String.t,
    arguments: [Blueprint.Input.Argument.t],
    source_location: nil | Blueprint.Document.SourceLocation.t,
    schema_node: nil | Absinthe.Type.Directive.t,
    flags: [atom],
    errors: [Phase.Error.t],
  }

  @spec expand(t, Blueprint.node_t, map) :: {t, map}
  def expand(%__MODULE__{schema_node: %{expand: nil}}, node, acc) do
    {node, acc}
  end
  def expand(%__MODULE__{schema_node: %{expand: fun}} = directive, node, acc) do
    args = Blueprint.Input.Argument.value_map(directive.arguments)
    fun.(args, node, acc)
  end
  def expand(%__MODULE__{schema_node: nil}, node, acc) do
    {node, acc}
  end

  @doc """
  Determine the placement name for a given Blueprint node
  """
  @spec placement(Blueprint.node_t) :: nil | atom
  def placement(%Blueprint.Document.Operation{type: type}), do: type
  def placement(%Blueprint.Document.Field{}), do: :field
  def placement(%Blueprint.Document.Fragment.Named{}), do: :fragment_definition
  def placement(%Blueprint.Document.Fragment.Spread{}), do: :fragment_spread
  def placement(%Blueprint.Document.Fragment.Inline{}), do: :inline_fragment
  def placement(_), do: nil

end
