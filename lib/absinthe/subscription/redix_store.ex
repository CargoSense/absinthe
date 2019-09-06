defmodule Absinthe.Subscription.RedixStore do
  @behaviour Absinthe.Subscription.Store

  @impl true
  def add_subscription(registry, key, subscription_id, doc) do
    registry_name = to_string(registry)
    binary_key = registry_name <> ":" <> :erlang.term_to_binary(key)
    subscription_key = registry_name <> ":" <> subscription_id

    {:ok, _} = Redix.command(:redix, ["MULTI"])

    try do
      {:ok, _} =
        Redix.command(:redix, [
          "HSET",
          binary_key,
          subscription_id,
          :erlang.term_to_binary(doc)
        ])

      Redix.command(:redix, [
        "SADD",
        subscription_key,
        binary_key
      ])
    after
      {:ok, _} = Redix.command(:redix, ["EXEC"])
    end
  end

  @impl true
  def remove_subscriptions(registry, subscription_id) do
    {:ok, _} = Redix.command(:redix, ["MULTI"])

    registry_name = to_string(registry)
    subscription_key = registry_name <> ":" <> subscription_id

    try do
      {:ok, keys} = Redix.command(:redix, ["SMEMBERS", subscription_key])

      for key <- keys do
        Redix.command(:redix, ["HDEL", key, subscription_id])
      end

      Redix.command(:redix, ["DEL", subscription_key])
    after
      {:ok, _} = Redix.command(:redix, ["EXEC"])
    end
  end

  @impl true
  def lookup_by_key(registry, key) do
    registry_name = to_string(registry)
    binary_key = registry_name <> ":" <> :erlang.term_to_binary(key)

    {:ok, docs} = Redix.command(:redix, ["HGETALL", binary_key])

    docs
    |> Enum.chunk_every(2)
    |> Map.new(fn [k, v] -> {k, :erlang.binary_to_term(v)} end)
  end

  @impl true
  def pool_size(_registry) do
    {:ok, 0}
  end
end
