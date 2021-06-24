defmodule Absinthe.Resolution do
  @moduledoc """
  Information about the current resolution. It is created by adding field specific
  information to the more general `%Absinthe.Blueprint.Execution{}` struct.

  In many ways like the `%Conn{}` from `Plug`, the `%Absinthe.Resolution{}` is the
  piece of information that passed along from middleware to middleware as part of
  resolution.

  ## Contents
  - `:adapter` - The adapter used for any name conversions.
  - `:definition` - The Blueprint definition for this field.
  - `:context` - The context passed to `Absinthe.run`.
  - `:root_value` - The root value passed to `Absinthe.run`, if any.
  - `:parent_type` - The parent type for the field.
  - `:private` - Operates similarly to the `:private` key on a `%Plug.Conn{}`
    and is a place for libraries (and similar) to store their information.
  - `:schema` - The current schema.
  - `:source` - The resolved parent object; source of this field.

  When a `%Resolution{}` is accessed via middleware, you may want to update the
  context (e.g. to cache a dataloader instance or the result of an ecto query).
  Updating the context can be done simply by using the map updating syntax (or
  `Map.put/3`):

  ```elixir
  %{resolution | context: new_context}
  # OR
  Map.put(resolution, :context, new_context)
  ```

  To access the schema type for this field, see the `definition.schema_node`.
  """

  @typedoc """
  The arguments that are passed from the schema. (e.g. id of the record to be
  fetched)
  """
  @type arguments :: %{optional(atom) => any}
  @type source :: any

  @type t :: %__MODULE__{
          value: term,
          errors: [term],
          adapter: Absinthe.Adapter.t(),
          context: map,
          root_value: any,
          schema: Absinthe.Schema.t(),
          definition: Absinthe.Blueprint.node_t(),
          parent_type: Absinthe.Type.t(),
          source: source,
          state: field_state,
          acc: %{any => any},
          extensions: %{any => any},
          arguments: arguments,
          fragments: [Absinthe.Blueprint.Document.Fragment.Named.t()]
        }

  defstruct [
    :value,
    :adapter,
    :context,
    :parent_type,
    :root_value,
    :definition,
    :schema,
    :source,
    errors: [],
    middleware: [],
    acc: %{},
    arguments: %{},
    extensions: %{},
    private: %{},
    path: [],
    state: :unresolved,
    fragments: [],
    fields_cache: %{}
  ]

  def resolver_spec(fun) do
    {{__MODULE__, :call}, fun}
  end

  @type field_state :: :unresolved | :resolved | :suspended

  @doc """
  Get the child fields under the current field.

  See `project/2` for details.
  """
  def project(info) do
    case info.definition.schema_node.type do
      %Absinthe.Type.Interface{} ->
        raise need_concrete_type_error()

      %Absinthe.Type.Union{} ->
        raise need_concrete_type_error()

      schema_node ->
        project(info, schema_node)
    end
  end

  @doc """
  Get the current path.

  Each `Absinthe.Resolution` struct holds the current result path as a list of
  blueprint nodes and indices. Usually however you don't need the full AST list
  and instead just want the path that will eventually end up in the result.

  For that, use this function.

  ## Examples
  Given some query:
  ```
  {users { email }}
  ```

  If you called this function inside a resolver on the users email field it
  returns a value like:

  ```elixir
  resolve fn _, _, resolution ->
    Absinthe.Resolution.path(resolution) #=> ["users", 5, "email"]
  end
  ```

  In this case `5` is the 0 based index in the list of users the field is currently
  at.
  """
  def path(%{path: path}) do
    path
    |> Enum.reverse()
    |> Enum.drop(1)
    |> Enum.map(&field_name/1)
  end

  defp field_name(%{alias: nil, name: name}), do: name
  defp field_name(%{alias: name}), do: name
  defp field_name(%{name: name}), do: name
  defp field_name(index), do: index

  @doc """
  Get the child fields under the current field.

  ## Example

  Given a document like:
  ```
  { user { id name }}
  ```

  ```
  field :user, :user do
    resolve fn _, info ->
      child_fields = Absinthe.Resolution.project(info) |> Enum.map(&(&1.name))
      # ...
    end
  end
  ```

  `child_fields` will be `["id", "name"]`.

  It correctly handles fragments, so for example if you had the document:
  ```
  {
    user {
      ... on User {
        id
      }
      ... on Named {
        name
      }
    }
  }
  ```

  you would still get a nice and simple `child_fields` that was `["id", "name"]`.
  """
  def project(
        %{
          definition: %{selections: selections},
          path: path,
          fields_cache: cache
        } = info,
        type
      ) do
    type = Absinthe.Schema.lookup_type(info.schema, type)

    {fields, _} = Absinthe.Resolution.Projector.project(selections, type, path, cache, info)

    fields
  end

  defp need_concrete_type_error() do
    """
    You tried to project from a field that is an abstract type without concrete type information!
    Use `project/2` instead of `project/1`, and supply the type yourself please!
    """
  end

  def call(%{state: :unresolved} = res, resolution_function) do
    result =
      case resolution_function do
        fun when is_function(fun, 2) ->
          fun.(res.arguments, res)

        fun when is_function(fun, 3) ->
          fun.(res.source, res.arguments, res)

        {mod, fun} ->
          apply(mod, fun, [res.source, res.arguments, res])

        _ ->
          raise Absinthe.ExecutionError, """
          Field resolve property must be a 2 arity anonymous function, 3 arity
          anonymous function, or a `{Module, :function}` tuple.

          Instead got: #{inspect(resolution_function)}

          Resolving field:

              #{res.definition.name}

          Defined at:

              #{res.definition.schema_node.__reference__.location.file}:#{
            res.definition.schema_node.__reference__.location.line
          }

          Info: #{inspect(res)}
          """
      end

    put_result(res, result)
  end

  def call(res, _), do: res

  def path_string(%__MODULE__{path: path}) do
    Enum.map(path, fn
      %{name: name, alias: alias} ->
        alias || name

      %{schema_node: schema_node} ->
        schema_node.name
    end)
  end

  @doc """
  Handy function for applying user function result tuples to a resolution struct

  User facing functions generally return one of several tuples like `{:ok, val}`
  or `{:error, reason}`. This function handles applying those various tuples
  to the resolution struct.

  The resolution state is updated depending on the tuple returned. `:ok` and
  `:error` tuples set the state to `:resolved`, whereas middleware tuples set it
  to `:unresolved`.

  This is useful for middleware that wants to handle user facing functions, but
  does not want to duplicate this logic.
  """
  def put_result(res, {:ok, value}) do
    %{res | state: :resolved, value: value}
  end

  def put_result(res, {:error, [{_, _} | _] = error_keyword}) do
    %{res | state: :resolved, errors: [error_keyword]}
  end

  def put_result(res, {:error, nil}) do
    put_result(res, {:error, ""})
  end

  def put_result(res, {:error, errors}) do
    %{res | state: :resolved, errors: List.wrap(errors)}
  end

  def put_result(res, {:plugin, module, opts}) do
    put_result(res, {:middleware, module, opts})
  end

  def put_result(res, {:middleware, module, opts}) do
    %{res | state: :unresolved, middleware: [{module, opts} | res.middleware]}
  end

  def put_result(res, result) do
    raise result_error(result, res.definition, res.source)
  end

  @doc false
  def result_error({:error, _} = value, field, source) do
    result_error(
      value,
      field,
      source,
      "You're returning an :error tuple, but did you forget to include a `:message`\nkey in every custom error (map or keyword list)?"
    )
  end

  def result_error(value, field, source) do
    result_error(
      value,
      field,
      source,
      "Did you forget to return a valid `{:ok, any}` | `{:error, error_value}` tuple?"
    )
  end

  @doc """
  TODO: Deprecate
  """
  def call(resolution_function, parent, args, field_info) do
    case resolution_function do
      fun when is_function(fun, 2) ->
        fun.(args, field_info)

      fun when is_function(fun, 3) ->
        fun.(parent, args, field_info)

      {mod, fun} ->
        apply(mod, fun, [parent, args, field_info])

      _ ->
        raise Absinthe.ExecutionError, """
        Field resolve property must be a 2 arity anonymous function, 3 arity
        anonymous function, or a `{Module, :function}` tuple.
        Instead got: #{inspect(resolution_function)}
        Info: #{inspect(field_info)}
        """
    end
  end

  def call(function, args, info) do
    call(function, info.source, args, info)
  end

  @error_detail """
  ## For a data result

  `{:ok, any}` result will do.

  ### Examples:

  A simple integer result:

      {:ok, 1}

  Something more complex:

      {:ok, %Model.Thing{some: %{complex: :data}}}

  ## For an error result

  One or more errors for a field can be returned in a single `{:error, error_value}` tuple.

  `error_value` can be:
  - A simple error message string.
  - A map containing `:message` key, plus any additional serializable metadata.
  - A keyword list containing a `:message` key, plus any additional serializable metadata.
  - A list containing multiple of any/all of these.
  - Any other value compatible with `to_string/1`.

  ### Examples

  A simple error message:

      {:error, "Something bad happened"}

  Multiple error messages:

      {:error, ["Something bad", "Even worse"]

  Single custom errors (note the required `:message` keys):

      {:error, message: "Unknown user", code: 21}
      {:error, %{message: "A database error occurred", details: format_db_error(some_value)}}

  Three errors of mixed types:

      {:error, ["Simple message", [message: "A keyword list error", code: 1], %{message: "A map error"}]}

  Generic handler for interoperability with errors from other libraries:

      {:error, :foo}
      {:error, 1.0}
      {:error, 2}

  ## To activate a plugin

  `{:plugin, NameOfPluginModule, term}` to activate a plugin.

  See `Absinthe.Resolution.Plugin` for more information.

  """
  def result_error(value, field, source, guess) do
    Absinthe.ExecutionError.exception("""
    Invalid value returned from resolver.

    Resolving field:

        #{field.name}

    Defined at:

        #{field.schema_node.__reference__.location.file}:#{
      field.schema_node.__reference__.location.line
    }

    Resolving on:

        #{inspect(source)}

    Got value:

        #{inspect(value)}

    ...

    #{guess}

    ...

    The result must be one of the following...

    #{@error_detail}
    """)
  end
end

defimpl Inspect, for: Absinthe.Resolution do
  import Inspect.Algebra

  def inspect(res, opts) do
    # TODO: better inspect representation
    inner =
      res
      |> Map.from_struct()
      |> Map.update!(:fields_cache, fn _ ->
        "#fieldscache<...>"
      end)
      |> Map.to_list()
      |> Inspect.List.inspect(opts)

    concat(["#Absinthe.Resolution<", inner, ">"])
  end
end
