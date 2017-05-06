defmodule Absinthe.Blueprint.TypeReferenceTest do
  use Absinthe.Case, async: true

  alias Absinthe.Blueprint

  context ".unwrap of Name" do

    it "is left intact" do
      name = %Blueprint.TypeReference.Name{name: "Foo"}
      assert Blueprint.TypeReference.unwrap(name) == name
    end

  end

  context ".unwrap of List" do

    it "extracts the inner name" do
      name = %Blueprint.TypeReference.Name{name: "Foo"}
      list = %Blueprint.TypeReference.List{of_type: name}
      assert Blueprint.TypeReference.unwrap(list) == name
    end

    it "extracts the inner name, even when multiple deep" do
      name = %Blueprint.TypeReference.Name{name: "Foo"}
      list_1 = %Blueprint.TypeReference.List{of_type: name}
      list_2 = %Blueprint.TypeReference.List{of_type: list_1}
      assert Blueprint.TypeReference.unwrap(list_2) == name
    end

  end

  context ".unwrap of NonNull" do

    it "extracts the inner name" do
      name = %Blueprint.TypeReference.Name{name: "Foo"}
      list = %Blueprint.TypeReference.NonNull{of_type: name}
      assert Blueprint.TypeReference.unwrap(list) == name
    end

    it "extracts the inner name, even when multiple deep" do
      name = %Blueprint.TypeReference.Name{name: "Foo"}
      non_null = %Blueprint.TypeReference.NonNull{of_type: name}
      list = %Blueprint.TypeReference.List{of_type: non_null}
      assert Blueprint.TypeReference.unwrap(list) == name
    end

  end

end
