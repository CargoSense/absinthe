defmodule Absinthe.MiddlewareTest do
  use Absinthe.Case, async: true

  defmodule Auth do
    def call(res, _) do
      case res.context do
        %{current_user: _} ->
          res

        _ ->
          res
          |> Absinthe.Resolution.put_result({:error, "unauthorized"})
      end
    end
  end

  defmodule Schema do
    use Absinthe.Schema

    alias Absinthe.MiddlewareTest

    def middleware(middleware, _field, %Absinthe.Type.Object{identifier: :secret_object}) do
      # can't inline due to Elixir bug.
      fun = &auth/2
      [fun | middleware]
    end

    def middleware(middleware, _field, _) do
      middleware
    end

    def auth(res, _) do
      case res.context do
        %{current_user: _} ->
          res

        _ ->
          res
          |> Absinthe.Resolution.put_result({:error, "unauthorized"})
      end
    end

    query do
      field :authenticated, :user do
        middleware MiddlewareTest.Auth

        resolve fn _, _, _ ->
          {:ok, %{name: "bob"}}
        end
      end

      field :public, :user do
        resolve fn _, _, _ ->
          {:ok, %{name: "bob", email: "secret"}}
        end
      end

      field :returns_private_object, :secret_object do
        resolve fn _, _, _ ->
          {:ok, %{key: "value"}}
        end
      end

      field :returns_nil_error, :secret_object do
        resolve fn _, _, _ ->
          {:error, nil}
        end
      end

      field :from_context, :string do
        middleware fn res, _ ->
          %{res | context: %{value: "yooooo"}}
        end

        resolve fn _, %{context: context} ->
          {:ok, context.value}
        end
      end

      field :path, :path do
        resolve fn _, _ -> {:ok, %{}} end
      end
    end

    object :path do
      field :path, :path, resolve: fn _, _ -> {:ok, %{}} end

      field :result, list_of(:string) do
        resolve fn _, info ->
          {:ok, Absinthe.Resolution.path_string(info)}
        end
      end
    end

    # keys in this object are made secret via the def middleware callback
    object :secret_object do
      field :key, :string
      field :key2, :string
    end

    object :user do
      field :email, :string do
        middleware MiddlewareTest.Auth
        middleware Absinthe.Middleware.MapGet, :email

        middleware fn res, _ ->
          # no-op, mostly making sure this form works
          res
        end
      end

      field :name, :string
    end
  end

  test "fails with authorization error when no current user" do
    doc = """
    {authenticated { name }}
    """

    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)

    assert [
             %{
               locations: [%{column: 2, line: 1}],
               message: "unauthorized",
               path: ["authenticated"]
             }
           ] == errors
  end

  test "email fails with authorization error when no current user" do
    doc = """
    {public { name email }}
    """

    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)

    assert [
             %{
               locations: [%{column: 16, line: 1}],
               message: "unauthorized",
               path: ["public", "email"]
             }
           ] == errors
  end

  test "query returns an error with a nil error message" do
    doc = """
    { returns_nil_error { key } }
    """

    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)

    assert [
             %{
               locations: [%{column: 3, line: 1}],
               message: "",
               path: ["returns_nil_error"]
             }
           ] == errors
  end

  test "email works when current user" do
    doc = """
    {public { name email }}
    """

    assert {:ok, %{data: data}} =
             Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})

    assert %{"public" => %{"email" => "secret", "name" => "bob"}} == data
  end

  test "secret object cant be accessed without a current user" do
    doc = """
    {returnsPrivateObject { key }}
    """

    assert {:ok, %{errors: errors}} = Absinthe.run(doc, __MODULE__.Schema)

    assert [
             %{
               locations: [%{column: 25, line: 1}],
               message: "unauthorized",
               path: ["returnsPrivateObject", "key"]
             }
           ] == errors
  end

  test "secret object can be accessed with a current user" do
    doc = """
    {returnsPrivateObject { key }}
    """

    assert {:ok, %{data: %{"returnsPrivateObject" => %{"key" => "value"}}}} ==
             Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})
  end

  test "it can modify the context" do
    doc = """
    {fromContext}
    """

    assert {:ok, %{data: data}} =
             Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})

    assert %{"fromContext" => "yooooo"} == data
  end

  test "it gets the path of the current field" do
    doc = """
    {foo: path { bar: path { result }}}
    """

    assert {:ok, %{data: data}} =
             Absinthe.run(doc, __MODULE__.Schema, context: %{current_user: %{}})

    assert %{"foo" => %{"bar" => %{"result" => ["result", "bar", "foo", "RootQueryType"]}}} ==
             data
  end
end
