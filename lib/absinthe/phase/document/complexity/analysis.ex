defmodule Absinthe.Phase.Document.Complexity.Analysis do
  @moduledoc false

  # Analyses document complexity.

  alias Absinthe.{Blueprint, Phase, Complexity, Type}

  use Absinthe.Phase

  @default_complexity 1

  @doc """
  Run complexity analysis.
  """
  @spec run(Blueprint.t(), Keyword.t()) :: Phase.result_t()
  def run(input, options \\ []) do
    if Keyword.get(options, :analyze_complexity, false) do
      do_run(input, options)
    else
      {:ok, input}
    end
  end

  defp do_run(input, options) do
    info = info_boilerplate(input, options)
    fragments = process_fragments(input, info)
    fun = &handle_node(&1, info, fragments)
    {:ok, Blueprint.postwalk(input, fun)}
  end

  defp process_fragments(input, info) do
    Enum.reduce(input.fragments, %{}, fn fragment, processed ->
      fun = &handle_node(&1, info, processed)
      fragment = Blueprint.postwalk(fragment, fun)
      Map.put(processed, fragment.name, fragment)
    end)
  end

  def handle_node(%Blueprint.Document.Fragment.Spread{name: name} = node, _info, fragments) do
    fragment = Map.fetch!(fragments, name)
    %{node | complexity: fragment.complexity}
  end

  def handle_node(
        %Blueprint.Document.Fragment.Named{selections: fields} = node,
        _info,
        _fragments
      ) do
    %{node | complexity: sum_complexity(fields)}
  end

  def handle_node(
        %Blueprint.Document.Fragment.Inline{selections: fields} = node,
        _info,
        _fragments
      ) do
    %{node | complexity: sum_complexity(fields)}
  end

  def handle_node(
        %Blueprint.Document.Field{
          complexity: nil,
          selections: fields,
          argument_data: args,
          schema_node: schema_node
        } = node,
        info,
        _fragments
      ) do
    # NOTE:
    # This really should be more nuanced. If this particular field's schema node
    # is a union type, right now the complexity of:
    # thisField {
    #   ... User { a b c}
    #   ... Dog { x y z }
    # }
    # would be the complexity of `|a, b, c, x, y, z|` despite the fact that it is
    # impossible for `a, b, c` to also happen with `x, y, z`
    #
    # However, if this schema node is an interface type things get complicated quickly.
    # You would have to evaluate the complexity for every possible type which can get
    # pretty unwieldy. For now, simple types it is.
    child_complexity = sum_complexity(fields)

    schema_node = %{
      schema_node
      | complexity: Type.function(schema_node, :complexity)
    }

    case field_complexity(schema_node, args, child_complexity, info, node) do
      complexity when is_integer(complexity) and complexity >= 0 ->
        %{node | complexity: complexity}

      other ->
        raise Absinthe.AnalysisError, field_value_error(node, other)
    end
  end

  def handle_node(%Blueprint.Document.Operation{complexity: nil, selections: fields} = node, _, _) do
    %{node | complexity: sum_complexity(fields)}
  end

  def handle_node(node, _, _) do
    node
  end

  defp field_complexity(%{complexity: nil}, _, child_complexity, _, _) do
    @default_complexity + child_complexity
  end

  defp field_complexity(%{complexity: complexity}, arg, child_complexity, _, _)
       when is_function(complexity, 2) do
    complexity.(arg, child_complexity)
  end

  defp field_complexity(%{complexity: complexity}, arg, child_complexity, info, node)
       when is_function(complexity, 3) do
    info = struct(Complexity, Map.put(info, :definition, node))
    complexity.(arg, child_complexity, info)
  end

  defp field_complexity(%{complexity: {mod, fun}}, arg, child_complexity, info, node) do
    info = struct(Complexity, Map.put(info, :definition, node))
    apply(mod, fun, [arg, child_complexity, info])
  end

  defp field_complexity(%{complexity: complexity}, _, _, _, _) do
    complexity
  end

  defp field_value_error(field, value) do
    """
    Invalid value returned from complexity analyzer.

    Analyzing field:

      #{field.name}

    Defined at:

      #{field.schema_node.__reference__.location.file}:#{field.schema_node.__reference__.location.line}

    Got value:

        #{inspect(value)}

    The complexity value must be a non negative integer.
    """
  end

  defp sum_complexity(fields) do
    Enum.reduce(fields, 0, &sum_complexity/2)
  end

  defp sum_complexity(%{complexity: complexity}, acc) when is_nil(complexity) do
    @default_complexity + acc
  end

  defp sum_complexity(%{complexity: complexity}, acc) when is_integer(complexity) do
    complexity + acc
  end

  # Execution context data that's common to all fields
  defp info_boilerplate(bp_root, options) do
    %{
      context: options[:context] || %{},
      root_value: options[:root_value] || %{},
      schema: bp_root.schema
    }
  end
end
