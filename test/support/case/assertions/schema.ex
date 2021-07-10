defmodule Absinthe.Case.Assertions.Schema do
  import ExUnit.Assertions

  def load_schema(name) do
    Code.require_file("test/support/fixtures/dynamic/#{name}.exs")
  end

  @doc """
  Assert a schema error occurs.

  ## Examples

  ```
  iex> assert_schema_error("schema-name", [%{phase: Absinthe.Schema.Rule.TheRuleHere, extra: :bar}])
  ```
  """
  def assert_schema_error(schema_name, patterns) do
    err =
      assert_raise Absinthe.Schema.Error, fn ->
        load_schema(schema_name)
      end

    patterns =
      patterns
      |> Enum.filter(fn pattern ->
        assert Enum.find(err.phase_errors, fn error ->
                 keys = Map.keys(pattern)
                 Map.take(error, keys) |> handle_path == pattern |> handle_path
               end),
               "Could not find error detail pattern #{inspect(pattern)}\n\nin\n\n#{inspect(err.phase_errors)}"
      end)

    assert length(patterns) == length(err.phase_errors)
  end

  defp handle_path(%{locations: locations} = map) do
    locations =
      Enum.map(locations, fn
        %{file: file} = location ->
          %{location | file: file |> Path.split() |> List.last()}

        location ->
          location
      end)

    %{map | locations: locations}
  end

  defp handle_path(map), do: map

  def assert_notation_error(name) do
    assert_raise(Absinthe.Schema.Notation.Error, fn ->
      load_schema(name)
    end)
  end
end
