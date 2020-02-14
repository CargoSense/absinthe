defmodule Mix.Tasks.Absinthe.Schema.SdlTest do
  use Absinthe.Case, async: true

  alias Mix.Tasks.Absinthe.Schema.Sdl, as: Task

  defmodule TestSchema do
    use Absinthe.Schema

    """
    schema {
      query: Query
    }

    type Query {
      helloWorld(name: String!): String
    }
    """
    |> import_sdl
  end

  @test_schema "Mix.Tasks.Absinthe.Schema.SdlTest.TestSchema"

  defmodule TestSchemaWithEmpty do
    use Absinthe.Schema

    @behaviour Absinthe.Schema

    query do
      field :hello_world, :empty do
        arg :name, non_null(:string)
      end
    end

    object :empty do
    end
  end

  @test_empty_schema "Mix.Tasks.Absinthe.Schema.SdlTest.TestSchemaWithEmpty"

  describe "absinthe.schema.sdl" do
    test "parses options" do
      argv = ["output.graphql", "--schema", @test_schema]

      opts = Task.parse_options(argv)

      assert opts.filename == "output.graphql"
      assert opts.schema == TestSchema
    end

    test "provides default options" do
      argv = ["--schema", @test_schema]

      opts = Task.parse_options(argv)

      assert opts.filename == "./schema.graphql"
      assert opts.schema == TestSchema
    end

    test "fails if no schema arg is provided" do
      argv = []
      catch_error(Task.parse_options(argv))
    end

    test "Generate schema" do
      argv = ["--schema", @test_schema]
      opts = Task.parse_options(argv)

      {:ok, schema} = Task.generate_schema(opts)
      assert schema =~ "helloWorld(name: String!): String"
    end

    test "Generate schema with empty object" do
      argv = ["--schema", @test_empty_schema]
      opts = Task.parse_options(argv)

      {:ok, schema} = Task.generate_schema(opts)
      assert schema =~ "helloWorld(name: String!): Empty"
      assert schema =~ "type Empty {"
    end
  end
end
