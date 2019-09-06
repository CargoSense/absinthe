defmodule Absinthe.Subscription.RegistryStore do
  @behaviour Absinthe.Subscription.Store

  @impl true
  def add_subscription(registry, field_key, doc_id, doc) do
    {:ok, _} = Registry.register(registry, field_key, {doc_id, doc})
    {:ok, _} = Registry.register(registry, doc_id, field_key)
  end

  @impl true
  def remove_subscriptions(registry, doc_id) do
    self = self()

    for {^self, field_key} <- Registry.lookup(registry, doc_id) do
      Registry.unregister_match(registry, field_key, {doc_id, :_})
    end

    Registry.unregister(registry, doc_id)
  end

  @impl true
  def lookup_by_key(registry, key) do
    Registry.lookup(registry, key)
    |> Enum.map(&elem(&1, 1))
    |> Map.new()
  end

  @impl true
  def pool_size(registry) do
    Registry.meta(registry, :pool_size)
  end
end
