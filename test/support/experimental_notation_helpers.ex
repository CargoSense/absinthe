defmodule ExperimentalNotationHelpers do

  alias Absinthe.Blueprint

  def lookup_type(mod, type_ident) do
    Blueprint.Schema.lookup_type(mod.__absinthe_blueprint__(), type_ident)
  end

  def lookup_field(mod, type_ident, field_ident) do
    type = Blueprint.Schema.lookup_type(mod.__absinthe_blueprint__(), type_ident)
    Enum.find(type.fields, fn
      %{identifier: ^field_ident} ->
        true
      _ ->
        false
    end)
  end

  def type_count(mod) do
    length(mod.__absinthe_blueprint__().types)
  end

end
