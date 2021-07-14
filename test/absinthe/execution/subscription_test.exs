defmodule Absinthe.Execution.SubscriptionTest do
  use Absinthe.Case

  import ExUnit.CaptureLog

  defmodule Schema do
    use Absinthe.Schema

    query do
      # Query type must exist
    end

    object :user do
      field :id, :id
      field :name, :string

      field :email, :string do
        resolve fn
          _, _, %{context: %{admin: true}} ->
            {:ok, "foo@example.com"}
          _, _, _ ->
            {:error, "unauthorized"}
        end
      end

      field :group, :group do
        resolve fn user, _, %{context: %{test_pid: pid}} ->
          batch({__MODULE__, :batch_get_group, pid}, nil, fn _results ->
            {:ok, user.group}
          end)
        end
      end
    end

    object :group do
      field :name, :string
    end

    def batch_get_group(test_pid, _) do
      # send a message to the test process every time we access this function.
      # if batching is working properly, it should only happen once.
      send(test_pid, :batch_get_group)
      %{}
    end

    subscription do
      field :raises, :string do
        config fn _, _ ->
          {:ok, topic: "*"}
        end

        resolve fn _, _, _ ->
          raise "boom"
        end
      end

      field :user, :user do
        arg :id, :id

        config fn args, _ ->
          {:ok, topic: args[:id] || "*"}
        end

        trigger :update_user,
          topic: fn user ->
            [user.id, "*"]
          end
      end

      field :thing, :string do
        arg :client_id, non_null(:id)

        config fn
          _args, %{context: %{authorized: false}} ->
            {:error, "unauthorized"}

          args, _ ->
            {
              :ok,
              topic: args.client_id
            }
        end
      end

      field :multiple_topics, :string do
        config fn _, _ ->
          {:ok, topic: ["topic_1", "topic_2", "topic_3"]}
        end
      end

      field :other_user, :user do
        arg :id, :id

        config fn
          args, %{context: %{context_id: context_id, document_id: document_id}} ->
            {:ok, topic: args[:id] || "*", context_id: context_id, document_id: document_id}

          args, %{context: %{context_id: context_id}} ->
            {:ok, topic: args[:id] || "*", context_id: context_id}
        end
      end

      field :relies_on_document, :string do
        config fn _, %{document: %Absinthe.Blueprint{} = document} ->
          %{type: :subscription, name: op_name} = Absinthe.Blueprint.current_operation(document)
          {:ok, topic: "*", context_id: "*", document_id: op_name}
        end
      end
    end

    mutation do
      field :update_user, :user do
        arg :id, non_null(:id)

        resolve fn _, %{id: id}, _ ->
          {:ok, %{id: id, name: "foo"}}
        end
      end
    end
  end

  setup_all do
    {:ok, _} = start_supervised(PubSub)
    {:ok, _} = start_supervised({Absinthe.Subscription, [PubSub]})
    :ok
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "can subscribe the current process" do
    client_id = "abc"

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               Schema,
               variables: %{"clientId" => client_id},
               context: %{pubsub: PubSub}
             )

    Absinthe.Subscription.publish(PubSub, "foo", thing: client_id)

    assert_receive({:broadcast, msg})

    assert %{
             event: "subscription:data",
             result: %{data: %{"thing" => "foo"}},
             topic: topic
           } == msg
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "can unsubscribe the current process" do
    client_id = "abc"

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               Schema,
               variables: %{"clientId" => client_id},
               context: %{pubsub: PubSub}
             )

    Absinthe.Subscription.unsubscribe(PubSub, topic)

    Absinthe.Subscription.publish(PubSub, "foo", thing: client_id)

    refute_receive({:broadcast, _})
  end

  @query """
  subscription {
    multipleTopics
  }
  """
  test "schema can provide multiple topics to subscribe to" do
    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               Schema,
               variables: %{},
               context: %{pubsub: PubSub}
             )

    msg = %{
      event: "subscription:data",
      result: %{data: %{"multipleTopics" => "foo"}},
      topic: topic
    }

    Absinthe.Subscription.publish(PubSub, "foo", multiple_topics: "topic_1")

    assert_receive({:broadcast, ^msg})

    Absinthe.Subscription.publish(PubSub, "foo", multiple_topics: "topic_2")

    assert_receive({:broadcast, ^msg})

    Absinthe.Subscription.publish(PubSub, "foo", multiple_topics: "topic_3")

    assert_receive({:broadcast, ^msg})
  end

  @query """
  subscription {
    multipleTopics
  }
  """
  test "unsubscription works when multiple topics are provided" do
    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               Schema,
               variables: %{},
               context: %{pubsub: PubSub}
             )

    Absinthe.Subscription.unsubscribe(PubSub, topic)

    Absinthe.Subscription.publish(PubSub, "foo", multiple_topics: "topic_1")

    refute_receive({:broadcast, _})

    Absinthe.Subscription.publish(PubSub, "foo", multiple_topics: "topic_2")

    refute_receive({:broadcast, _})

    Absinthe.Subscription.publish(PubSub, "foo", multiple_topics: "topic_3")

    refute_receive({:broadcast, _})
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId, extra: 1)
  }
  """
  test "can return errors properly" do
    assert {
             :ok,
             %{
               errors: [
                 %{
                   locations: [%{column: 30, line: 2}],
                   message:
                     "Unknown argument \"extra\" on field \"thing\" of type \"RootSubscriptionType\"."
                 }
               ]
             }
           } ==
             run_subscription(@query, Schema,
               variables: %{"clientId" => "abc"},
               context: %{pubsub: PubSub}
             )
  end

  @query """
  subscription ($userId: ID!) {
    user(id: $userId) { id name }
  }
  """
  test "subscription triggers work" do
    id = "1"

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               Schema,
               variables: %{"userId" => id},
               context: %{pubsub: PubSub}
             )

    mutation = """
    mutation ($userId: ID!) {
      updateUser(id: $userId) { id name }
    }
    """

    assert {:ok, %{data: _}} =
             run_subscription(mutation, Schema,
               variables: %{"userId" => id},
               context: %{pubsub: PubSub}
             )

    assert_receive({:broadcast, msg})

    assert %{
             event: "subscription:data",
             result: %{data: %{"user" => %{"id" => "1", "name" => "foo"}}},
             topic: topic
           } == msg
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "can return an error tuple from the topic function" do
    assert {:ok, %{errors: [%{locations: [%{column: 3, line: 2}], message: "unauthorized"}]}} ==
             run_subscription(
               @query,
               Schema,
               variables: %{"clientId" => "abc"},
               context: %{pubsub: PubSub, authorized: false}
             )
  end

  @query """
  subscription Example {
    reliesOnDocument
  }
  """
  test "topic function receives a document" do
    assert {:ok, %{"subscribed" => _topic}} =
             run_subscription(@query, Schema, context: %{pubsub: PubSub})
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "stringifies topics" do
    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(@query, Schema,
               variables: %{"clientId" => "1"},
               context: %{pubsub: PubSub}
             )

    Absinthe.Subscription.publish(PubSub, "foo", thing: 1)

    assert_receive({:broadcast, msg})

    assert %{
             event: "subscription:data",
             result: %{data: %{"thing" => "foo"}},
             topic: topic
           } == msg
  end

  test "isn't tripped up if one of the subscription docs raises" do
    assert {:ok, %{"subscribed" => _}} = run_subscription("subscription { raises }", Schema)

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription("subscription { thing(clientId: \"*\")}", Schema)

    error_log =
      capture_log(fn ->
        Absinthe.Subscription.publish(PubSub, "foo", raises: "*", thing: "*")

        assert_receive({:broadcast, msg})

        assert %{
                 event: "subscription:data",
                 result: %{data: %{"thing" => "foo"}},
                 topic: topic
               } == msg
      end)

    assert String.contains?(error_log, "boom")
  end

  test "subscription docs with different contexts don't leak context" do
    ctx1 = %{test_pid: self(), user: 1}

    assert {:ok, %{"subscribed" => doc1}} =
             run_subscription("subscription { user { group { name } id} }", Schema, context: ctx1)

    ctx2 = %{test_pid: self(), user: 2}
    # different docs required for test, otherwise they get deduplicated from the start
    assert {:ok, %{"subscribed" => doc2}} =
             run_subscription("subscription { user { group { name } id name} }", Schema,
               context: ctx2
             )

    user = %{id: "1", name: "Alicia", group: %{name: "Elixir Users"}}

    Absinthe.Subscription.publish(PubSub, user, user: ["*", user.id])

    assert_receive({:broadcast, %{topic: ^doc1, result: %{data: _}}})
    assert_receive({:broadcast, %{topic: ^doc2, result: %{data: %{"user" => user}}}})

    assert user["group"]["name"] == "Elixir Users"

    # we should get this twice since the different contexts prevent batching.
    assert_receive(:batch_get_group)
    assert_receive(:batch_get_group)
  end

  describe "subscription_ids" do
    @query """
    subscription {
      otherUser { id }
    }
    """
    test "subscriptions with the same context_id and same source document have the same subscription_id" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription(@query, Schema, context: %{context_id: "logged-in"})

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription(@query, Schema, context: %{context_id: "logged-in"})

      assert doc1 == doc2
    end

    @query """
    subscription {
      otherUser { id }
    }
    """
    test "subscriptions with different context_id but the same source document have different subscription_ids" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription(@query, Schema, context: %{context_id: "logged-in"})

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription(@query, Schema, context: %{context_id: "not-logged-in"})

      assert doc1 != doc2
    end

    test "subscriptions with same context_id but different source document have different subscription_ids" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription("subscription { otherUser { id name } }", Schema,
                 context: %{context_id: "logged-in"}
               )

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription("subscription { otherUser { id } }", Schema,
                 context: %{context_id: "logged-in"}
               )

      assert doc1 != doc2
    end

    test "subscriptions with different context_id and different source document have different subscription_ids" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription("subscription { otherUser { id name } }", Schema,
                 context: %{context_id: "logged-in"}
               )

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription("subscription { otherUser { id } }", Schema,
                 context: %{context_id: "not-logged-in"}
               )

      assert doc1 != doc2
    end

    @query """
    subscription($id: ID!) { otherUser(id: $id) { id } }
    """
    test "subscriptions with the same variables & document have the same subscription_ids" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription(@query, Schema,
                 variables: %{"id" => "123"},
                 context: %{context_id: "logged-in"}
               )

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription(@query, Schema,
                 variables: %{"id" => "123"},
                 context: %{context_id: "logged-in"}
               )

      assert doc1 == doc2
    end

    @query """
    subscription($id: ID!) { otherUser(id: $id) { id } }
    """
    test "subscriptions with different variables but same document have different subscription_ids" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription(@query, Schema,
                 variables: %{"id" => "123"},
                 context: %{context_id: "logged-in"}
               )

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription(@query, Schema,
                 variables: %{"id" => "456"},
                 context: %{context_id: "logged-in"}
               )

      assert doc1 != doc2
    end

    test "document_id can be provided to override the default logic for deriving document_id" do
      assert {:ok, %{"subscribed" => doc1}} =
               run_subscription("subscription { otherUser { id name } }", Schema,
                 context: %{context_id: "logged-in", document_id: "abcdef"}
               )

      assert {:ok, %{"subscribed" => doc2}} =
               run_subscription("subscription { otherUser { name id } }", Schema,
                 context: %{context_id: "logged-in", document_id: "abcdef"}
               )

      assert doc1 == doc2
    end
  end

  @query """
  subscription ($clientId: ID!) {
    thing(clientId: $clientId)
  }
  """
  test "subscription executes telemetry events", context do
    client_id = "abc"

    :telemetry.attach_many(
      context.test,
      [
        [:absinthe, :execute, :operation, :start],
        [:absinthe, :execute, :operation, :stop],
        [:absinthe, :subscription, :publish, :start],
        [:absinthe, :subscription, :publish, :stop]
      ],
      fn event, measurements, metadata, config ->
        send(self(), {event, measurements, metadata, config})
      end,
      %{}
    )

    assert {:ok, %{"subscribed" => topic}} =
             run_subscription(
               @query,
               Schema,
               variables: %{"clientId" => client_id},
               context: %{pubsub: PubSub}
             )

    assert_receive {[:absinthe, :execute, :operation, :start], measurements, %{id: id}, _config}
    assert System.convert_time_unit(measurements[:system_time], :native, :millisecond)

    assert_receive {[:absinthe, :execute, :operation, :stop], _, %{id: ^id}, _config}

    Absinthe.Subscription.publish(PubSub, "foo", thing: client_id)
    assert_receive({:broadcast, msg})

    assert %{
             event: "subscription:data",
             result: %{data: %{"thing" => "foo"}},
             topic: topic
           } == msg

    # Subscription events
    assert_receive {[:absinthe, :subscription, :publish, :start], _, %{id: id}, _config}
    assert_receive {[:absinthe, :subscription, :publish, :stop], _, %{id: ^id}, _config}

    :telemetry.detach(context.test)
  end

  defp run_subscription(query, schema, opts \\ []) do
    opts = Keyword.update(opts, :context, %{pubsub: PubSub}, &Map.put(&1, :pubsub, PubSub))

    case run(query, schema, opts) do
      {:ok, %{"subscribed" => topic}} = val ->
        PubSub.subscribe(topic)
        val

      val ->
        val
    end
  end
end
