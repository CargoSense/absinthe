defmodule Absinthe.Phase.Subscription.SubscribeSelf do
  use Absinthe.Phase
  alias Absinthe.Phase

  @moduledoc false

  alias Absinthe.Blueprint

  @spec run(any, Keyword.t()) :: {:ok, Blueprint.t()}
  def run(blueprint, options) do
    with %{type: :subscription} = op <- Blueprint.current_operation(blueprint) do
      do_subscription(op, blueprint, options)
    else
      _ -> {:ok, blueprint}
    end
  end

  def do_subscription(%{type: :subscription} = op, blueprint, options) do
    context = blueprint.execution.context
    pubsub = ensure_pubsub!(context)

    %{selections: [field]} = op

    with {:ok, config} <- get_config(field, context, blueprint) do
      field_keys = get_field_keys(field, config)
      context_id = get_context_id(config)
      document_id = get_document_id(config, blueprint, options)

      subscription_id = subscription_id(context_id, document_id)

      for field_key <- field_keys do
        Absinthe.Subscription.subscribe(pubsub, blueprint, field_key, context_id, subscription_id)
      end

      {:replace, blueprint,
       [
         {Phase.Subscription.Result, topic: subscription_id},
         {Phase.Telemetry, Keyword.put(options, :event, [:execute, :operation, :stop])}
       ]}
    else
      {:error, error} ->
        blueprint = update_in(blueprint.execution.validation_errors, &[error | &1])

        error_pipeline = [
          {Phase.Document.Result, options}
        ]

        {:replace, blueprint, error_pipeline}
    end
  end

  defp get_config(
         %{schema_node: schema_node, argument_data: argument_data} = field,
         context,
         blueprint
       ) do
    name = schema_node.identifier

    config =
      case Absinthe.Type.function(schema_node, :config) do
        fun when is_function(fun, 2) ->
          apply(fun, [argument_data, %{context: context, document: blueprint}])

        fun when is_function(fun, 1) ->
          IO.write(
            :stderr,
            "Warning: 1-arity topic functions are deprecated, upgrade to 2 arity before 1.4.0 release"
          )

          apply(fun, [argument_data])

        nil ->
          {:ok, topic: Atom.to_string(name)}
      end

    case config do
      {:ok, config} ->
        {:ok, config}

      {:error, msg} ->
        error = %Phase.Error{
          phase: __MODULE__,
          message: msg,
          locations: [field.source_location]
        }

        {:error, error}

      val ->
        raise """
        Invalid return from config function!

        A config function must return `{:ok, config}` or `{:error, msg}`. You returned:

        #{inspect(val)}
        """
    end
  end

  defp get_field_keys(%{schema_node: schema_node} = _field, config) do
    name = schema_node.identifier

    find_field_keys!(config)
    |> Enum.map(fn key -> {name, key} end)
  end

  defp ensure_pubsub!(context) do
    case Absinthe.Subscription.extract_pubsub(context) do
      {:ok, pubsub} ->
        pubsub

      _ ->
        raise """
        Pubsub not configured!

        Subscriptions require a configured pubsub module.
        """
    end
  end

  defp find_field_keys!(config) do
    topic =
      config[:topic] ||
        raise """
        Subscription config must include a non null topic!

        #{inspect(config)}
        """

    case topic do
      [] ->
        raise """
        Subscription config must not provide an empty list of topics!

        #{inspect(config)}
        """

      val ->
        List.wrap(val)
        |> Enum.map(&to_string/1)
    end
  end

  defp subscription_id(context_id, document_id) do
    "__absinthe__:doc:#{context_id}:#{document_id}"
  end

  defp get_context_id(config) do
    context_id = config[:context_id] || :erlang.unique_integer()
    to_string(context_id)
  end

  defp get_document_id(config, blueprint, options) do
    case config[:document_id] do
      nil ->
        binary =
          {blueprint.source || blueprint.input, options[:variables] || %{}}
          |> :erlang.term_to_binary()

        :crypto.hash(:sha256, binary)
        |> Base.encode16()

      val ->
        val
    end
  end
end
