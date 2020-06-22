defmodule Absinthe.Blueprint.Schema do
  @moduledoc false

  alias __MODULE__

  alias Absinthe.Blueprint

  @type directive_t :: Schema.DirectiveDefinition.t()

  @type type_t ::
          Blueprint.Schema.EnumTypeDefinition.t()
          | Blueprint.Schema.InputObjectTypeDefinition.t()
          | Blueprint.Schema.InterfaceTypeDefinition.t()
          | Blueprint.Schema.ObjectTypeDefinition.t()
          | Blueprint.Schema.ScalarTypeDefinition.t()
          | Blueprint.Schema.UnionTypeDefinition.t()

  @type t ::
          Blueprint.Schema.EnumValueDefinition.t()
          | Blueprint.Schema.InputValueDefinition.t()
          | Blueprint.Schema.SchemaDeclaration.t()
          | Blueprint.Schema.SchemaDefinition.t()
          | type_t()
          | directive_t()

  @doc """
  Lookup a type definition that is part of a schema.
  """
  @spec lookup_type(Blueprint.t(), atom) :: nil | Blueprint.Schema.t()
  def lookup_type(blueprint, identifier) do
    blueprint.schema_definitions
    |> List.first()
    |> Map.get(:type_definitions)
    |> Enum.find(fn
      %{identifier: ^identifier} ->
        true

      _ ->
        false
    end)
  end

  @doc """
  Lookup a directive definition that is part of a schema.
  """
  @spec lookup_directive(Blueprint.t(), atom) :: nil | Blueprint.Schema.directive_t()
  def lookup_directive(blueprint, identifier) do
    blueprint.schema_definitions
    |> List.first()
    |> Map.get(:directive_definitions)
    |> Enum.find(fn
      %{identifier: ^identifier} ->
        true

      _ ->
        false
    end)
  end

  def functions(module) do
    if function_exported?(module, :functions, 0) do
      module.functions
    else
      []
    end
  end

  def build([%Absinthe.Blueprint{} = bp | attrs]) do
    build_types(attrs, [bp], [])
  end

  defp build_types([], [bp], buffer) do
    if buffer != [] do
      raise """
      Unused buffer! #{inspect(buffer)}
      """
    end

    Map.update!(bp, :schema_definitions, &Enum.reverse/1)
  end

  # this rather insane scheme lets interior macros get back out to exterior
  # scopes so that they can define top level entities as necessary, and then
  # return to the regularly scheduled programming.
  defp build_types([:stash | rest], [head | tail], buff) do
    build_types(rest, tail, [head | buff])
  end

  defp build_types([:pop | rest], remaining, [head | buff]) do
    build_types(rest, [head | remaining], buff)
  end

  defp build_types([%Schema.SchemaDefinition{} = schema | rest], stack, buff) do
    build_types(rest, [schema | stack], buff)
  end

  @simple_open [
    Schema.ScalarTypeDefinition,
    Schema.ObjectTypeDefinition,
    Schema.FieldDefinition,
    Schema.EnumTypeDefinition,
    Schema.DirectiveDefinition,
    Schema.InputObjectTypeDefinition,
    Schema.InputValueDefinition,
    Schema.InterfaceTypeDefinition,
    Schema.UnionTypeDefinition,
    Schema.EnumValueDefinition
  ]

  defp build_types([%module{} = type | rest], stack, buff) when module in @simple_open do
    build_types(rest, [type | stack], buff)
  end

  defp build_types([{:extend, identifier} | rest], [schema | _] = stack, buff) do
    type = Enum.find(schema.type_definitions, &(&1.identifier == identifier))
    build_types(rest, [type | stack], [:extend | buff])
  end

  defp build_types([{:import_fields, criterion} | rest], [obj | stack], buff) do
    build_types(rest, [push(obj, :imports, criterion) | stack], buff)
  end

  defp build_types([{:desc, desc} | rest], [item | stack], buff) do
    build_types(rest, [%{item | description: desc} | stack], buff)
  end

  defp build_types([{:middleware, middleware} | rest], [field, obj | stack], buff) do
    field = Map.update!(field, :middleware, &(middleware ++ &1))
    build_types(rest, [field, obj | stack], buff)
  end

  defp build_types([{:config, config} | rest], [field | stack], buff) do
    field = %{field | config: config}
    build_types(rest, [field | stack], buff)
  end

  defp build_types([{:trigger, trigger} | rest], [field | stack], buff) do
    field = Map.update!(field, :triggers, &[trigger | &1])
    build_types(rest, [field | stack], buff)
  end

  defp build_types([{:interface, interface} | rest], [obj | stack], buff) do
    obj = Map.update!(obj, :interfaces, &[interface | &1])
    build_types(rest, [obj | stack], buff)
  end

  defp build_types([{:__private__, private} | rest], [entity | stack], buff) do
    entity = Map.update!(entity, :__private__, &update_private(&1, private))
    build_types(rest, [entity | stack], buff)
  end

  defp build_types([{:values, values} | rest], [enum | stack], buff) do
    enum = Map.update!(enum, :values, &(values ++ &1))
    build_types(rest, [enum | stack], buff)
  end

  defp build_types([{:sdl, sdl_definitions} | rest], [schema | stack], buff) do
    # TODO: Handle directives, etc
    build_types(rest, [push(schema, :type_definitions, sdl_definitions) | stack], buff)
  end

  defp build_types([{:locations, locations} | rest], [directive | stack], buff) do
    directive = Map.update!(directive, :locations, &(locations ++ &1))
    build_types(rest, [directive | stack], buff)
  end

  defp build_types([{:types, types} | rest], [union | stack], buff) do
    union = Map.update!(union, :types, &(types ++ &1))
    build_types(rest, [union | stack], buff)
  end

  defp build_types([{attr, value} | rest], [entity | stack], buff) do
    entity = %{entity | attr => value}
    build_types(rest, [entity | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.EnumValueDefinition{} = value, enum | stack], buff) do
    build_types(rest, [push(enum, :values, value) | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.InputValueDefinition{} = arg, field | stack], buff) do
    arg = Map.update!(arg, :default_value, fn val -> {:unquote, [], [val]} end)
    build_types(rest, [push(field, :arguments, arg) | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.FieldDefinition{} = field, obj | stack], buff) do
    field =
      field
      |> Map.update!(:middleware, &Enum.reverse/1)
      |> Map.update!(:arguments, &Enum.reverse/1)
      |> Map.update!(:triggers, &{:%{}, [], &1})
      |> Map.put(:function_ref, {obj.identifier, field.identifier})

    build_types(rest, [push(obj, :fields, field) | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.ObjectTypeDefinition{} = obj, schema | stack], buff) do
    obj = Map.update!(obj, :fields, &Enum.reverse/1)
    {schema, buff} = modify(schema, :type_definitions, obj, buff)
    build_types(rest, [schema | stack], buff)
  end

  defp build_types(
         [:close | rest],
         [%Schema.InputObjectTypeDefinition{} = obj, schema | stack],
         buff
       ) do
    obj = Map.update!(obj, :fields, &Enum.reverse/1)
    {schema, buff} = modify(schema, :type_definitions, obj, buff)
    build_types(rest, [schema | stack], buff)
  end

  defp build_types(
         [:close | rest],
         [%Schema.InterfaceTypeDefinition{} = iface, schema | stack],
         buff
       ) do
    iface = Map.update!(iface, :fields, &Enum.reverse/1)
    {schema, buff} = modify(schema, :type_definitions, iface, buff)
    build_types(rest, [schema | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.UnionTypeDefinition{} = union, schema | stack], buff) do
    {schema, buff} = modify(schema, :type_definitions, union, buff)
    build_types(rest, [schema | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.DirectiveDefinition{} = dir, schema | stack], buff) do
    build_types(rest, [push(schema, :directive_definitions, dir) | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.ScalarTypeDefinition{} = type, schema | stack], buff) do
    build_types(rest, [push(schema, :type_definitions, type) | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.EnumTypeDefinition{} = type, schema | stack], buff) do
    {schema, buff} = modify(schema, :type_definitions, type, buff)
    build_types(rest, [schema | stack], buff)
  end

  defp build_types([:close | rest], [%Schema.SchemaDefinition{} = schema, bp], buff) do
    bp = push(bp, :schema_definitions, schema)
    build_types(rest, [bp], buff)
  end

  def modify(entity, key, val, [:extend | buff]) do
    {replace(entity, key, val), buff}
  end

  def modify(entity, key, val, buff) do
    {push(entity, key, val), buff}
  end

  defp push(entity, key, value) when is_list(value) do
    Map.update!(entity, key, &(&1 ++ value))
  end

  defp push(entity, key, value) do
    Map.update!(entity, key, &[value | &1])
  end

  defp replace(entity, key, %{identifier: identifier} = type) do
    new_value =
      entity
      |> Map.get(key)
      |> Enum.map(fn
        %{identifier: ^identifier} -> type
        other -> other
      end)

    %{entity | key => new_value}
  end

  defp update_private(existing_private, private) do
    Keyword.merge(existing_private, private, fn
      _, v1, v2 ->
        update_private(v1, v2)
    end)
  end
end
