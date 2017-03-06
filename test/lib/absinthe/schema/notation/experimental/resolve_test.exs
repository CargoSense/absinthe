defmodule Absinthe.Schema.Notation.Experimental.ResolveTest do
  use Absinthe.Case
  import ExperimentalNotationHelpers


  defmodule Definition do
    use Absinthe.Schema.Notation.Experimental

    object :obj do

      field :anon_literal, :boolean do
        resolve fn
          _, _, _ ->
            {:ok, true}
        end
      end

      field :local_private, :boolean do
        resolve &local_private/3
      end

      field :local_public, :boolean do
        resolve &local_public/3
      end

      field :remote, :boolean do
        resolve &Absinthe.Schema.Notation.Experimental.ResolveTest.remote_resolve/3
      end

      field :remote_ref, :boolean do
        resolve {Absinthe.Schema.Notation.Experimental.ResolveTest, :remote_resolve}
      end

      field :invocation_result, :boolean do
        resolve mapping(:foo)
      end

    end

    defp local_private(_, _, _) do
      {:ok, true}
    end

    def local_public(_, _, _) do
      {:ok, true}
    end

    def mapping(_) do
      fn
        _, _, _ ->
          {:ok, true}
      end
    end

  end

  def remote_resolve(_, _, _) do
    {:ok, true}
  end

  def assert_resolver(field_identifier) do
    %{resolve_ast: resolver} = lookup_field(Definition, :obj, field_identifier)
    assert resolver
  end

  describe "resolve" do
    describe "when given an anonymous function literal" do
      it "adds the resolver to the field" do
        assert_resolver(:anon_literal)
      end
    end
    describe "when given a local private function capture" do
      it "adds the resolver to the field" do
        assert_resolver(:local_private)
      end
    end
    describe "when given a local public function capture" do
      it "adds the resolver to the field" do
        assert_resolver(:local_public)
      end
    end
    describe "when given a remote public function capture" do
      it "adds the resolver to the field" do
        assert_resolver(:remote)
      end
    end
    describe "when given a remote ref" do
      it "adds the resolver to the field" do
        assert_resolver(:remote_ref)
      end
    end
    describe "when given the result of a function invocation" do
      it "adds the resolver to the field" do
        assert_resolver(:invocation_result)
      end
    end
  end

end
