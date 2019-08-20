defmodule Absinthe.ResolutionTest do
  use Absinthe.Case, async: true

  defmodule Schema do
    use Absinthe.Schema

    interface :named do
      field :name, :string

      resolve_type fn _, _ -> :user end
    end

    object :user do
      interface :named
      field :id, :id
      field :name, :string
    end

    object :member do
      interface :named
      field :mid, :id
      field :name, :string
    end

    union :union_named do
      types [:user, :member]

      resolve_type fn
        _, _ -> :user
      end
    end

    query do
      field :user, :user do
        resolve fn _, info ->
          fields = Absinthe.Resolution.project(info) |> Enum.map(& &1.name)

          # ghetto escape hatch
          send(self(), {:fields, fields})
          {:ok, nil}
        end
      end

      field :named, :named do
        resolve fn _, info ->
          fields = Absinthe.Resolution.project(info) |> Enum.map(& &1.name)

          # ghetto escape hatch
          send(self(), {:fields, fields})
          {:ok, nil}
        end
      end

      field :union_result, :union_named do
        resolve fn _, info ->
          fields = Absinthe.Resolution.project(info) |> Enum.map(& &1.name)

          # ghetto escape hatch
          send(self(), {:fields, fields})
          {:ok, nil}
        end
      end

      field :invalid_resolver, :string do
        resolve("bogus")
      end
    end
  end

  test "project/1 works" do
    doc = """
    { user { id name } }
    """

    {:ok, _} = Absinthe.run(doc, Schema)

    assert_receive({:fields, fields})

    assert ["id", "name"] == fields
  end

  test "project/1 works with fragments and things" do
    doc = """
    {
      user {
        ... on User {
          id
        }

        ... on Named {
          name
        }
      }
    }
    """

    {:ok, _} = Absinthe.run(doc, Schema)

    assert_receive({:fields, fields})

    assert ["id", "name"] == fields
  end

  test "project/1 works with interfaces" do
    doc = """
    {
      named {
        ... on User {
          id
        }

        name

        ... on Member {
          mid
        }
      }
    }
    """

    {:ok, _} = Absinthe.run(doc, Schema)

    assert_receive({:fields, fields})

    assert ["id", "name", "mid"] == fields
  end

  test "project/1 works with unions" do
    doc = """
    {
      union_result {
        ... on User {
          id
          name
        }

        ... on Member {
          mid
          name
        }
      }
    }
    """

    {:ok, _} = Absinthe.run(doc, Schema)

    assert_receive({:fields, fields})

    assert ["id", "name", "mid"] == fields
  end

  test "invalid resolver" do
    doc = """
    { invalidResolver }
    """

    assert_raise Absinthe.ExecutionError,
                 ~r/Field resolve property must be a 2 arity anonymous function, 3 arity\nanonymous function, or a `{Module, :function}` tuple.\n\nInstead got: \"bogus\"\n\nResolving field:\n\n    invalidResolver/,
                 fn ->
                   {:ok, _} = Absinthe.run(doc, Schema)
                 end
  end
end
