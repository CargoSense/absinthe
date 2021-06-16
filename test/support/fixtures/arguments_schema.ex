defmodule Absinthe.Fixtures.ArgumentsSchema do
  use Absinthe.Schema
  use Absinthe.Fixture

  @res %{
    true: "YES",
    false: "NO"
  }

  scalar :any, open_ended: true do
    parse fn value -> {:ok, value} end
    serialize fn value -> value end
  end

  scalar :input_name do
    parse fn %{value: value} -> {:ok, %{first_name: value}} end
    serialize fn %{first_name: name} -> name end
  end

  scalar :input_name_raising do
    parse fn %{__struct__: struct} ->
      raise "inputNameRaising scalar parse was called for #{struct}"
    end
  end

  scalar :name do
    serialize &to_string/1

    parse fn
      %Absinthe.Blueprint.Input.String{} = string ->
        string.value

      _ ->
        :error
    end
  end

  input_object :boolean_input_object do
    field :flag, :boolean
  end

  input_object :contact_input do
    field :email, non_null(:string)
    field :contact_type, :contact_type
    field :default_with_string, :string, default_value: "asdf"
    field :nested_contact_input, :nested_contact_input
  end

  input_object :nested_contact_input do
    field :email, non_null(:string)
  end

  enum :contact_type do
    value :email, name: "Email", as: "Email"
    value :phone
    value :sms, deprecate: "Use phone instead"
  end

  input_object :input_stuff do
    field :value, :integer
    field :non_null_field, non_null(:string)
  end

  input_object :filter do
    field :include, list_of(:integer)
    field :exclude, list_of(:integer)
  end

  query do
    field :entities, list_of(:any) do
      arg :representations, non_null(list_of(non_null(:any)))

      resolve fn %{representations: representations}, _ ->
        {:ok, representations}
      end
    end

    field :stuff, :integer do
      arg :stuff, non_null(:input_stuff)

      resolve fn _, _ ->
        {:ok, 14}
      end
    end

    field :filter_numbers, list_of(:integer) do
      arg :filter_empty, :filter, default_value: %{}
      arg :filter_include, :filter, default_value: %{include: [1, 2, 3]}
      arg :filter_exclude, :filter, default_value: %{exclude: [1, 2, 3]}
      arg :filter_all, :filter, default_value: %{include: [1], exclude: [2, 3]}
    end

    field :test_boolean_input_object, :boolean do
      arg :input, non_null(:boolean_input_object)

      resolve fn %{input: input}, _ ->
        {:ok, input[:flag]}
      end
    end

    field :contact, :contact_type do
      arg :type, :contact_type

      resolve fn args, _ -> {:ok, Map.get(args, :type)} end
    end

    field :contacts, list_of(:string) do
      arg :contacts, non_null(list_of(:contact_input))

      resolve fn %{contacts: contacts}, _ ->
        {:ok, Enum.map(contacts, &Map.get(&1, :email))}
      end
    end

    field :names, list_of(:input_name) do
      arg :names, list_of(:input_name)

      resolve fn %{names: names}, _ -> {:ok, names} end
    end

    field :list_of_lists, list_of(list_of(:string)) do
      arg :items, list_of(list_of(:string))

      resolve fn %{items: items}, _ ->
        {:ok, items}
      end
    end

    field :numbers, list_of(:integer) do
      arg :numbers, list_of(:integer)

      resolve fn %{numbers: numbers}, _ ->
        {:ok, numbers}
      end
    end

    field :user, :string do
      arg :contact, :contact_input

      resolve fn
        %{contact: %{email: email} = contact}, _ ->
          {:ok, "#{email}#{contact[:default_with_string]}"}

        args, _ ->
          {:error, "Got #{inspect(args)} instead"}
      end
    end

    field :something,
      type: :string,
      args: [
        name: [type: :input_name],
        flag: [type: :boolean, default_value: false]
      ],
      resolve: fn
        %{name: %{first_name: name}}, _ ->
          {:ok, name}

        %{flag: val}, _ ->
          {:ok, @res[val]}

        _, _ ->
          {:error, "No value provided for flag argument"}
      end

    field :required_thing, :string do
      arg :name, non_null(:input_name)

      resolve fn
        %{name: %{first_name: name}}, _ -> {:ok, name}
        args, _ -> {:error, "Got #{inspect(args)} instead"}
      end
    end

    field :raising_thing, :string do
      arg :name, :input_name_raising
    end

    field :company, :string do
      arg :name, :string, default_value: nil

      resolve fn
        %{name: name}, _ ->
          {:ok, name}

        _args, _ ->
          {:error, "could not find your default nil arg"}
      end
    end
  end
end
