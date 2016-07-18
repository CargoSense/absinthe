defmodule Absinthe.Blueprint.Document.Fragment.Inline do

  alias Absinthe.Blueprint

  @enforce_keys [:type_condition]
  defstruct [
    :type_condition,
    selections: [],
    directives: [],
    source_location: nil,
    # Populated by phases
    schema_node: nil,
    fields: [],
    errors: [],
  ]

  @type t :: %__MODULE__{
    directives: [Blueprint.Directive.t],
    errors: [Absinthe.Phase.Error.t],
    fields: [Blueprint.Document.Field.t],
    selections: [Blueprint.Document.selection_t],
    schema_node: nil | Absinthe.Type.t,
    source_location: nil | Blueprint.Document.SourceLocation.t,
    type_condition: Blueprint.TypeReference.Name.t,
  }

end
