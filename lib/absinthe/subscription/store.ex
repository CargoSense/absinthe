defmodule Absinthe.Subscription.Store do
  @moduledoc """
  Store behaviour expected by Absinthe to power subscriptions
  """

  @type t :: module()

  @doc """
  Add a subscription for the given key, subscription ID and document
  to the store.
  """
  @callback add_subscription(
              registry :: module,
              key :: term,
              subscription_id :: binary,
              doc :: map
            ) :: {:ok, any} | {:error, any}

  @doc """
  Remove all subscriptions for the given subscription ID from the store.
  """
  @callback remove_subscriptions(registry :: module, subscription_id :: binary) ::
              {:ok, any} | {:error, any}

  @doc """
  Look up all subscriptions for the given key in the store.

  Return a map from subscription ID to document.
  """
  @callback lookup_by_key(registry :: module, key :: term) ::
              {:ok, %{required(binary) => map}} | {:error, any}

  @doc """
  Return the proxy pool size.
  """
  @callback pool_size(registry :: module) :: {:ok, integer} | {:error, any}
end
