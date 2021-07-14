defmodule PubSub do
  @behaviour Absinthe.Subscription.Pubsub

  def child_spec(opts) do
    opts =
      opts
      |> Keyword.merge(keys: :unique, name: __MODULE__)

    Registry.child_spec(opts)
  end

  def node_name() do
    node()
  end

  def subscribe(topic) do
    Registry.register(__MODULE__, topic, [])
    :ok
  end

  def publish_subscription(topic, data) do
    message = %{
      topic: topic,
      event: "subscription:data",
      result: data
    }

    Registry.dispatch(__MODULE__, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:broadcast, message})
    end)
  end

  def publish_mutation(_proxy_topic, _mutation_result, _subscribed_fields) do
    # this pubsub is local and doesn't support clusters
    :ok
  end
end
