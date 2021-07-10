defmodule Absinthe.Schema.Notation.ImportTest do
  use Absinthe.Case, async: true

  defp field_list(module, name) do
    module.__absinthe_type__(name).fields
    |> Enum.filter(&(!introspection?(&1)))
    |> Keyword.keys()
    |> Enum.sort()
  end

  defp introspection?({_, field}) do
    Absinthe.Type.introspection?(field)
  end

  alias Absinthe.Phase

  describe "import fields" do
    test "fields can be imported" do
      defmodule Foo do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :foo do
          field :name, :string
        end

        object :bar do
          import_fields :foo
          field :email, :string
        end
      end

      assert [:email, :name] = field_list(Foo, :bar)
    end

    test "works for input objects" do
      defmodule InputFoo do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        input_object :foo do
          field :name, :string
        end

        input_object :bar do
          import_fields :foo
          field :email, :string
        end
      end

      fields = InputFoo.__absinthe_type__(:bar).fields

      assert [:email, :name] = fields |> Map.keys() |> Enum.sort()
    end

    test "works for interfaces" do
      defmodule InterfaceFoo do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :cool_fields do
          field :name, :string
        end

        interface :foo do
          import_fields :cool_fields
          resolve_type fn _, _ -> :real_foo end
        end

        object :real_foo do
          interface :foo
          import_fields :cool_fields
        end
      end

      assert [:name] = field_list(InterfaceFoo, :foo)

      assert [:name] = field_list(InterfaceFoo, :real_foo)
    end

    test "can work transitively" do
      defmodule Bar do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :foo do
          field :name, :string
        end

        object :bar do
          import_fields :foo
          field :email, :string
        end

        object :baz do
          import_fields :bar
          field :age, :integer
        end
      end

      assert [:age, :email, :name] == field_list(Bar, :baz)
    end

    test "raises errors nicely" do
      defmodule ErrorSchema do
        use Absinthe.Schema

        @pipeline_modifier Absinthe.Schema.Notation.ImportTest

        object :bar do
          import_fields :asdf
          field :email, :string
        end
      end

      assert {:error,
              [
                %Absinthe.Phase.Error{
                  extra: %{},
                  locations: [_],
                  message:
                    "In Bar, :asdf is not defined in your schema.\n\nTypes must exist if referenced.\n",
                  path: [],
                  phase: Absinthe.Phase.Schema.Validation.TypeReferencesExist
                }
              ]} = validate(ErrorSchema)
    end

    test "handles circular errors" do
      defmodule Circles do
        use Absinthe.Schema

        @pipeline_modifier Absinthe.Schema.Notation.ImportTest

        object :foo do
          import_fields :bar
          field :name, :string
        end

        object :bar do
          import_fields :foo
          field :email, :string
        end
      end

      assert {:error,
              [
                %Absinthe.Phase.Error{
                  extra: :bar,
                  locations: [
                    %{
                      line: _
                    }
                  ],
                  message:
                    "Field Import Cycle Error\n\nField Import in object `bar' `import_fields([foo: []]) forms a cycle via: ([:bar, :foo, :bar])",
                  path: [],
                  phase: Absinthe.Phase.Schema.Validation.NoCircularFieldImports
                },
                %Absinthe.Phase.Error{
                  extra: :foo,
                  locations: [
                    %{
                      line: _
                    }
                  ],
                  message:
                    "Field Import Cycle Error\n\nField Import in object `foo' `import_fields([bar: []]) forms a cycle via: ([:foo, :bar, :foo])",
                  path: [],
                  phase: Absinthe.Phase.Schema.Validation.NoCircularFieldImports
                }
              ]} = validate(Circles)
    end

    test "can import types from more than one thing" do
      defmodule Multiples do
        use Absinthe.Schema

        object :foo do
          field :name, :string
        end

        object :bar do
          field :email, :string
        end

        query do
          import_fields :foo
          import_fields :bar
          field :age, :integer
        end
      end

      assert [:age, :email, :name] == field_list(Multiples, :query)
    end

    test "can import fields from imported types" do
      defmodule Source1 do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :foo do
          field :name, :string
        end
      end

      defmodule Source2 do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        object :bar do
          field :email, :string
        end
      end

      defmodule Dest do
        use Absinthe.Schema

        query do
          # Query type must exist
        end

        import_types Source1
        import_types Source2

        object :baz do
          import_fields :foo
          import_fields :bar
        end
      end

      assert [:email, :name] = field_list(Dest, :baz)
    end
  end

  describe "unknown imported modules" do
    test "returns error" do
      assert_schema_error("unknown_import_schema", [
        %Absinthe.Phase.Error{
          message: "could not load module Test.Unknown due to reason :nofile",
          phase: Absinthe.Phase.Schema.TypeImports
        }
      ])
    end
  end

  defp validate(schema) do
    pipeline =
      schema
      |> Absinthe.Pipeline.for_schema()
      |> Absinthe.Pipeline.upto(Phase.Schema.FieldImports)
      |> Kernel.++([Phase.Schema.Validation.Result])

    case Absinthe.Pipeline.run(schema.__absinthe_blueprint__, pipeline) do
      {ok_or_error, val, _} ->
        {ok_or_error, val}
    end
  end

  def pipeline(_pipeline) do
    []
  end
end
