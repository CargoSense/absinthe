defmodule Absinthe.Type.Interface do
  @moduledoc """
  A defined interface type that represent a list of named fields and their
  arguments.

  Fields on an interface have the same rules as fields on an
  `Absinthe.Type.Object`.

  If an `Absinthe.Type.Object` lists an interface in its `:interfaces` entry,
  it guarantees that it defines the same fields and arguments that the
  interface does.

  Because sometimes it's for the interface to determine the implementing type of
  a resolved object, you must either:

  * Provide a `:resolve_type` function on the interface
  * Provide a `:is_type_of` function on each implementing type

  ```
  interface :named_entity do
    field :name, :string
    resolve_type fn
      %{age: _}, _ -> :person
      %{employee_count: _}, _ -> :business
      _, _ -> nil
    end
  end

  object :person do
    field :name, :string
    field :age, :string

    interface :named_entity
  end

  object :business do
    field :name, :string
    field :employee_count, :integer

    interface :named_entity
  end
  ```
  """

  use Absinthe.Introspection.TypeKind, :interface

  alias Absinthe.Type
  alias Absinthe.Schema

  @typedoc """
  * `:name` - The name of the interface type. Should be a TitleCased `binary`. Set automatically.
  * `:description` - A nice description for introspection.
  * `:fields` - A map of `Absinthe.Type.Field` structs. See `Absinthe.Schema.Notation.field/4` and
  * `:args` - A map of `Absinthe.Type.Argument` structs. See `Absinthe.Schema.Notation.arg/2`.
  * `:resolve_type` - A function used to determine the implementing type of a resolved object. See also `Absinthe.Type.Object`'s `:is_type_of`.

  The `:resolve_type` function will be passed two arguments; the object whose type needs to be identified, and the `Absinthe.Execution` struct providing the full execution context.

  The `__private__` and `:__reference__` keys are for internal use.
  """
  @type t :: %__MODULE__{
          name: binary,
          description: binary,
          fields: map,
          identifier: atom,
          interfaces: [Absinthe.Type.Interface.t()],
          __private__: Keyword.t(),
          definition: module,
          __reference__: Type.Reference.t()
        }

  defstruct name: nil,
            description: nil,
            fields: nil,
            identifier: nil,
            resolve_type: nil,
            interfaces: [],
            __private__: [],
            definition: nil,
            __reference__: nil

  @doc false
  defdelegate functions, to: Absinthe.Blueprint.Schema.InterfaceTypeDefinition

  @spec resolve_type(Type.Interface.t(), any, Absinthe.Resolution.t()) :: Type.t() | nil
  def resolve_type(type, obj, env, opts \\ [lookup: true])

  def resolve_type(interface, obj, %{schema: schema} = env, opts) do
    implementors = Schema.implementors(schema, interface.identifier)

    if resolver = Type.function(interface, :resolve_type) do
      case resolver.(obj, env) do
        nil ->
          nil

        ident when is_atom(ident) ->
          if opts[:lookup] do
            Absinthe.Schema.lookup_type(schema, ident)
          else
            ident
          end
      end
    else
      type_name =
        implementors
        |> Enum.filter(&match?(%Type.Object{}, &1))
        |> Enum.find(fn type ->
          Absinthe.Type.function(type, :is_type_of).(obj)
        end)

      if opts[:lookup] do
        Absinthe.Schema.lookup_type(schema, type_name)
      else
        type_name
      end
    end
  end

  @doc """
  Whether the interface (or implementors) are correctly configured to resolve
  objects.
  """
  @spec type_resolvable?(Schema.t(), t) :: boolean
  def type_resolvable?(schema, %{resolve_type: nil} = iface) do
    Schema.implementors(schema, iface)
    |> Enum.all?(& &1.is_type_of)
  end

  def type_resolvable?(_, %{resolve_type: _}) do
    true
  end

  @doc false
  @spec member?(t, Type.t()) :: boolean
  def member?(%{identifier: ident}, %{interfaces: ifaces}) do
    ident in ifaces
  end

  def member?(_, _) do
    false
  end
end
