defmodule Absinthe.Subscription.Pubsub do
  @moduledoc """
  Pubsub behaviour expected by Absinthe to power subscriptions

  A subscription includes a GraphQL query document that resolves to a set of 
  objects and fields. When the subscription is triggered, Absinthe will run the
  document and publish the resolved objects to subscribers through a module that
  implements the behaviour defined here.

  Each application is free to implement the PubSub behavior in its own way.  
  For example, the absinthe_phoenix project implements the subscription pubsub
  using Phoenix.PubSub by way of the application's Endpoint.  Regardless 
  of the underlying mechanisms, the implementation should maintain the type 
  signatures and expected behaviors of the callbacks below.
  """

  @type t :: module()

  @doc """
  Subscribe the current process for messages about the given topic.
  """
  @callback subscribe(topic :: binary) :: term

  @doc """
  An Absinthe.Subscription.Pubsub system may extend across multiple nodes
  connected by some mechanism. Regardless of this mechanism, all nodes should
  have unique names.

  Absinthe invokes `node_name` function to get current node's name. If you
  are running inside erlang cluster, you can use `Kernel.node/0` as a node
  name.
  """
  @callback node_name() :: binary

  @doc """
  An Absinthe.Subscription.Pubsub system may extend across multiple nodes.
  Processes need only subscribe to the pubsub process that
  is running on their own node.

  However, mutations can happen on any node in the custer and must to be 
  broadcast to other nodes so that they can also reevaluate their GraphQL 
  subscriptions and notify subscribers on that node.

  When told of a mutation, Absinthe invokes the `publish_mutation` function 
  on the node in which the mutation is processed first. The function should
  publish a message to the given `proxy_topic`, with the identity of node 
  on which the mutation occurred included in the broadcast message.

  The message broadcast should be a map that contains, at least

      %{
          node: node_name,      # should be equal to `node_name/0`
          mutation_result: …,   # from arguments
          subscribed_fields: …  # from arguments

          # other fields as needed
      }

  """
  @callback publish_mutation(
              proxy_topic :: binary,
              mutation_result :: term,
              subscribed_fields :: list
            ) :: term

  @doc """
  After a mutation is published, and Absinthe has re-run the necessary GraphQL 
  subscriptions to generate a new set of resolved data, it calls
  `publish_subscription`.

  Your pubsub implementation should publish a message to the given topic, with
  the newly resolved data. The broadcast should be limited to the current node 
  only.
  """
  @callback publish_subscription(topic :: binary, data :: map, context :: map) :: term

  @doc """
  Return the storage module.
  """
  @callback store() :: module
end
