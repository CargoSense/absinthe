defmodule Absinthe.Resolution.Plugin.AsyncTest do
  use Absinthe.Case, async: true

  defmodule Schema do
    use Absinthe.Schema

    query do
      field :async_thing, :string do
        resolve fn _, _, _ ->
          async(fn ->
            {:ok, "we async now"}
          end)
        end
      end

      field :other_async_thing, :string do
        resolve cool_async fn _, _, _ ->
          {:ok, "magic"}
        end
      end
    end

    def cool_async(fun) do
      fn source, args, info ->
        async(fn ->
          fun.(source, args, info)
        end)
      end
    end

  end

  it "can resolve a field using the normal async helper" do
    doc = """
    {asyncThing}
    """
    assert {:ok, %{data: %{"asyncThing" => "we async now"}}} == Absinthe.run(doc, Schema)
  end

  it "can resolve a field using a cooler but probably confusing to some people helper" do
    doc = """
    {otherAsyncThing}
    """
    assert {:ok, %{data: %{"otherAsyncThing" => "magic"}}} == Absinthe.run(doc, Schema)
  end

end
