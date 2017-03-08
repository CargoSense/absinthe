defmodule Absinthe.Resolution do
  @moduledoc """
  The primary struct of resolution.

  In many ways like the `%Conn{}` from `Plug`, the `%Absinthe.Resolution{}` is the
  piece of information that passed along from middleware to middleware as part of
  resolution.
  """

  @typedoc """
  Information about the current resolution.

  ## Contents
  - `:adapter` - The adapter used for any name conversions.
  - `:definition` - The Blueprint definition for this field.
  - `:context` - The context passed to `Absinthe.run`.
  - `:root_value` - The root value passed to `Absinthe.run`, if any.
  - `:parent_type` - The parent type for the field.
  - `:schema` - The current schema.
  - `:source` - The resolved parent object; source of this field.

  To access the schema type for this field, see the `definition.schema_node`.
  """
  @type t :: %__MODULE__{
    value: term,
    errors: [term],
    adapter: Absinthe.Adapter.t,
    context: map,
    root_value: any,
    schema: Schema.t,
    definition: Blueprint.node_t,
    parent_type: Type.t,
    source: any,
    state: field_state,
    acc: %{any => any},
  }

  @enforce_keys [:adapter, :context, :root_value, :schema, :source]
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
    private: %{},
    state: :unresolved,
  ]

  def resolver_spec(fun) do
    {{__MODULE__, :call}, fun}
  end

  @type field_state :: :unresolved | :resolved | :suspended

  def call(%{state: :unresolved} = res, resolution_function) do
    result = case resolution_function do
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

        Instead got: #{inspect resolution_function}

        Info: #{inspect res}
        """
    end

    put_result(res, result)
  end
  def call(res, _), do: res

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
      value, field, source,
      "You're returning an :error tuple, but did you forget to include a `:message`\nkey in every custom error (map or keyword list)?"
    )
  end
  def result_error(value, field, source) do
    result_error(
      value, field, source,
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
        Instead got: #{inspect resolution_function}
        Info: #{inspect field_info}
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

        #{field.schema_node.__reference__.location.file}:#{field.schema_node.__reference__.location.line}

    Resolving on:

        #{inspect source}

    Got value:

        #{inspect value}

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
    inner =
      res
      |> Map.from_struct
      |> Map.update!(:definition, &(&1.name))
      |> Map.update!(:parent_type, &(&1.identifier))
      |> Map.to_list
      |> Inspect.List.inspect(opts)

    concat ["#Absinthe.Resolution<", inner, ">"]
  end
end
