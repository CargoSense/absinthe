defmodule Absinthe.Subscription.Local do
  @moduledoc """
  This module handles broadcasting documents that are local to this node
  """

  require Logger

  alias Absinthe.Pipeline.BatchResolver

  # This module handles running and broadcasting documents that are local to this
  # node.

  @doc """
  Publish a mutation to the local node only.

  See also `Absinthe.Subscription.publish/3`
  """
  @spec publish_mutation(
          Absinthe.Subscription.Pubsub.t(),
          term,
          [Absinthe.Subscription.subscription_field_spec()]
        ) :: :ok
  def publish_mutation(pubsub, mutation_result, subscribed_fields) do
    docs_and_topics =
      for {field, key_strategy} <- subscribed_fields,
          {topic, doc} <- get_docs(pubsub, field, mutation_result, key_strategy) do
        {{topic, {field, key_strategy}}, put_in(doc.execution.root_value, mutation_result)}
      end

    docs_by_context = group_by_context(docs_and_topics)

    for docset <- docs_by_context do
      run_docset(pubsub, docset)
    end

    :ok
  end

  defp group_by_context(docs_and_topics) do
    docs_and_topics
    |> Enum.group_by(fn {_, doc} -> doc.execution.context end)
    |> Map.values()
  end

  defp run_docset(pubsub, docs_and_topics) do
    {topics, docs} = Enum.unzip(docs_and_topics)

    docs =
      BatchResolver.run(docs,
        schema: hd(docs).schema,
        abort_on_error: false,
        initial_phases: [{Absinthe.Phase.Telemetry, [:subscription, :publish, :start]}]
      )

    pipeline = [
      Absinthe.Phase.Document.Result,
      {Absinthe.Phase.Telemetry, [:subscription, :publish]}
    ]

    for {doc, {topic, key_strategy}} <- Enum.zip(docs, topics), doc != :error do
      try do
        {:ok, %{result: data}, _} = Absinthe.Pipeline.run(doc, pipeline)

        Logger.debug("""
        Absinthe Subscription Publication
        Field Topic: #{inspect(key_strategy)}
        Subscription id: #{inspect(topic)}
        Data: #{inspect(data)}
        """)

        :ok = pubsub.publish_subscription(topic, data, doc.execution.context)
      rescue
        e ->
          BatchResolver.pipeline_error(e, System.stacktrace())
      end
    end
  end

  defp get_docs(pubsub, field, mutation_result, topic: topic_fun)
       when is_function(topic_fun, 1) do
    do_get_docs(pubsub, field, topic_fun.(mutation_result))
  end

  defp get_docs(pubsub, field, _mutation_result, key) do
    do_get_docs(pubsub, field, key)
  end

  defp do_get_docs(pubsub, field, keys) do
    keys
    |> List.wrap()
    |> Enum.map(&to_string/1)
    |> Enum.flat_map(&Absinthe.Subscription.get(pubsub, {field, &1}))
  end
end
