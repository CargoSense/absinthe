defmodule Absinthe.Blueprint.IDL.ArgumentDefinition do

  alias Absinthe.{Blueprint, Language}

  defstruct [
    name: nil,
    default_value: nil,
    type: nil,
    errors: [],
    ast_node: nil
  ]

  @type t :: %__MODULE__{
    name: String.t,
    default_value: any,
    type: Blueprint.type_reference_t,
    errors: [Blueprint.Error.t],
    ast_node: nil | Language.t
  }

  def from_ast(%Language.InputValueDefinition{} = node, doc) do
    %__MODULE__{
      name: node.name,
      default_value: ast_default_value(node.default_value, doc),
      type: Blueprint.type_from_ast_type(node.type, doc),
      ast_node: node
    }
  end

  @spec ast_default_value(nil | Language.input_t, Language.Document.t) :: nil | Blueprint.Input.t
  defp ast_default_value(nil, _), do: nil
  defp ast_default_value(node, doc), do: Blueprint.Input.from_ast(node, doc)

end
