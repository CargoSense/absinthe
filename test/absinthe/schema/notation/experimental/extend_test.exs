defmodule Absinthe.Schema.Notation.Experimental.ExtendTest do
  use Absinthe.Case
  import ExperimentalNotationHelpers

  @moduletag :experimental

  defmodule Definition do
    use Absinthe.Schema.Notation

    object :my_object do
      field :foo, :string
    end

    extend :my_object do
      field :bar, :string
    end

    interface :my_interface do
      field :foo, :string
    end

    extend :my_interface do
      field :bar, :string
    end

    input_object :my_input_object do
      field :foo, :string
    end

    extend :my_input_object do
      field :bar, :string
    end

    enum :my_enum do
      value :one
    end

    extend :my_enum do
      value :two
    end
  end

  describe "extend" do
    test "object" do
      assert %{fields: fields} = lookup_type(Definition, :my_object)

      field_identifiers = Enum.map(fields, & &1.identifier)
      assert :foo in field_identifiers
      assert :bar in field_identifiers
    end

    test "interface" do
      assert %{fields: fields} = lookup_type(Definition, :my_interface)

      field_identifiers = Enum.map(fields, & &1.identifier)
      assert :foo in field_identifiers
      assert :bar in field_identifiers
    end

    test "input_object" do
      assert %{fields: fields} = lookup_type(Definition, :my_input_object)

      field_identifiers = Enum.map(fields, & &1.identifier)
      assert :foo in field_identifiers
      assert :bar in field_identifiers
    end

    test "enum" do
      assert %{values: values} = lookup_type(Definition, :my_enum)

      value_identifiers = Enum.map(values, & &1.identifier)
      assert :one in value_identifiers
      assert :two in value_identifiers
    end

    test "applies placement rules!" do
      assert_notation_error(
        "PlacementRules",
        """
        interface :my_interface do
          field :foo, :string
        end

        extend :my_interface do
          field :bar, :string
          arg :input, :string
        end
        """,
        "Invalid schema notation: `arg` must only be used within `directive`, `field`"
      )
    end
  end

  def assert_notation_error(name, text, message) do
    assert_raise(Absinthe.Schema.Notation.Error, message, fn ->
      """
      defmodule MyTestSchema.#{name} do
        use Absinthe.Schema

        query do
          #Query type must exist
        end

        #{text}
      end
      """
      |> Code.eval_string()
    end)
  end
end
