defmodule Absinthe.Phase.Blueprint do
  use Absinthe.Phase

  alias Absinthe.Blueprint

  @spec run(any, Keyword.t) :: {:ok, Blueprint.t}
  def run(input, _) do
    doc = input # The doc is also the input
    {:ok, Blueprint.Draft.convert(input, doc)}
  end

end
