defmodule Absinthe.Type.InterfaceTest do
  use Absinthe.Case, async: true

  defmodule Schema do
    use Absinthe.Schema

    query do
      field :foo, type: :foo
      field :bar, type: :bar

      field :named_thing, :named do
        resolve fn _, _ ->
          {:ok, %{}}
        end
      end
    end

    object :foo do
      field :name, :string

      is_type_of fn _ ->
        true
      end

      interface :named
    end

    object :bar do
      field :name, :string

      is_type_of fn _ ->
        true
      end

      interface :named
    end

    # NOT USED IN THE QUERY
    object :baz do
      field :name, :string

      is_type_of fn _ ->
        true
      end

      interfaces [:named]
    end

    interface :named do
      description "An interface"
      field :name, :string

      resolve_type fn _, _ ->
        # just a value
        nil
      end
    end
  end

  describe "interface" do
    test "can be defined" do
      obj = Schema.__absinthe_type__(:named)
      assert %Absinthe.Type.Interface{name: "Named", description: "An interface"} = obj
      assert Absinthe.Type.function(obj, :resolve_type)
    end

    test "captures the relationships in the schema" do
      implementors = Map.get(Schema.__absinthe_interface_implementors__(), :named, [])
      assert :foo in implementors
      assert :bar in implementors
      # Not directly in query, but because it's
      # an available type and there's a field that
      # defines the interface as a type
      assert :baz in implementors
    end

    test "can find implementors" do
      obj = Schema.__absinthe_type__(:named)
      assert length(Absinthe.Schema.implementors(Schema, obj)) == 3
    end
  end

  describe "an object that implements an interface" do
    @graphql """
    query {
      contact {
        entity { name }
      }
    }
    """
    test "with the interface as a field type, can select fields that are declared by the interface" do
      assert_data(
        %{"contact" => %{"entity" => %{"name" => "Bruce"}}},
        run(@graphql, Absinthe.Fixtures.ContactSchema)
      )
    end

    @graphql """
    query {
      contact {
        entity { name age }
      }
    }
    """
    test "with the interface as a field type, can't select fields from an implementing type without 'on'" do
      assert_error_message(
        ~s(Cannot query field "age" on type "NamedEntity". Did you mean to use an inline fragment on "Person"?),
        run(@graphql, Absinthe.Fixtures.ContactSchema)
      )
    end

    @graphql """
    query {
      contact {
        entity {
          name
          ... on Person { age }
        }
      }
    }
    """
    test "with the interface as a field type, can select fields from an implementing type with 'on'" do
      assert_data(
        %{"contact" => %{"entity" => %{"name" => "Bruce", "age" => 35}}},
        run(@graphql, Absinthe.Fixtures.ContactSchema)
      )
    end
  end

  describe "when it doesn't define those fields" do
    alias Absinthe.Phase.Schema.Validation

    test "reports schema errors" do
      assert_schema_error("bad_interface_schema", [
        %{
          phase: Validation.ObjectMustImplementInterfaces,
          extra: %{object: :foo, interface: :aged, fields: [:age]}
        },
        %{
          phase: Validation.ObjectMustImplementInterfaces,
          extra: %{object: :foo, interface: :named, fields: [:name]}
        },
        %{
          phase: Validation.ObjectInterfacesMustBeValid,
          extra: %{object: :quux, interface: :foo}
        },
        %{phase: Validation.InterfacesMustResolveTypes, extra: :named}
      ])
    end
  end

  defmodule InterfaceSchema do
    use Absinthe.Schema

    # Example data
    @box %{
      item: %{name: "Computer", cost: 1000}
    }

    query do
      field :box,
        type: :box,
        args: [],
        resolve: fn _, _ ->
          {:ok, @box}
        end
    end

    object :box do
      field :item, :valued_item
      interface :has_item
      is_type_of fn _ -> true end
    end

    interface :has_item do
      field :item, :item
    end

    object :valued_item do
      field :name, :string
      field :cost, :integer

      interface :item
      is_type_of fn _ -> true end
    end

    interface :item do
      field :name, :string
    end
  end

  @graphql """
  query {
    box {
      item {
        name
        cost
      }
    }
  }
  """
  test "can query an interface field type's fields" do
    assert_data(
      %{"box" => %{"item" => %{"name" => "Computer", "cost" => 1000}}},
      run(@graphql, InterfaceSchema)
    )
  end

  @graphql """
  query {
    box {
      ... on HasItem {
        item {
          name
        }
      }
    }
  }
  """
  test "can query an interface field using a fragment and access its type's fields" do
    assert_data(%{"box" => %{"item" => %{"name" => "Computer"}}}, run(@graphql, InterfaceSchema))
  end

  @graphql """
  query {
    box {
      ... on HasItem {
        item {
          name
          ... on ValuedItem {
            cost
          }
        }
      }
    }
  }
  """
  test "can query InterfaceSubtypeSchema treating box as HasItem and item as ValuedItem" do
    assert_data(
      %{"box" => %{"item" => %{"name" => "Computer", "cost" => 1000}}},
      run(@graphql, InterfaceSchema)
    )
  end

  @graphql """
  query {
    box {
      ... on HasItem {
        item {
          name
          cost
        }
      }
    }
  }
  """
  test "rejects querying InterfaceSubtypeSchema treating box as HasItem asking for cost" do
    assert_error_message(
      ~s(Cannot query field "cost" on type "Item". Did you mean to use an inline fragment on "ValuedItem"?),
      run(@graphql, InterfaceSchema)
    )
  end

  @graphql """
  query {
    namedThing {
      name
    }
  }
  """
  test "works even when resolve_type returns nil" do
    assert_data(%{"namedThing" => %{}}, run(@graphql, Schema))
  end

  defmodule NestedInterfacesSchema do
    use Absinthe.Schema

    interface :root do
      field :root, :string
    end

    interface :intermediate do
      field :root, :string
      field :intermediate, :string

      interface :root
    end

    # Name starts with Z to order it to the back of the list of types
    object :z_child do
      field :root, :string
      field :intermediate, :string
      field :child, :string

      interface :root
      interface :intermediate

      is_type_of fn _entry -> true end
    end

    query do
      field :root, :root do
        resolve fn _, _, _ -> {:ok, %{}} end
      end
    end
  end

  @graphql """
  query GetRoot {
    root {
      __typename
    }
  }
  """

  test "resolved type of nested interfaces" do
    assert_data(%{"root" => %{"__typename" => "ZChild"}}, run(@graphql, NestedInterfacesSchema))
  end
end
