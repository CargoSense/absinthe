defmodule Absinthe.Subscription.Supervisor do
  @moduledoc false

  use Supervisor

  def start_link(pubsub, pool_size \\ System.schedulers_online() * 2) do
    pubsub =
      case pubsub do
        [module] when is_atom(module) ->
          module

        module ->
          module
      end

    Supervisor.start_link(__MODULE__, {pubsub, pool_size})
  end

  def init({pubsub, pool_size}) do
    meta = [pool_size: pool_size]

    children = [
      {Registry,
       [
         keys: :unique,
         name: Absinthe.Subscription.registry_name(pubsub, :unique),
         partitions: System.schedulers_online(),
         meta: meta,
         compressed: true
       ]},
      {Registry,
       [
         keys: :duplicate,
         name: Absinthe.Subscription.registry_name(pubsub, :duplicate),
         partitions: System.schedulers_online(),
         compressed: true
       ]},
      {Absinthe.Subscription.ProxySupervisor, [pubsub, pool_size]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
