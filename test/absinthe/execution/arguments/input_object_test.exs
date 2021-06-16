defmodule Absinthe.Execution.Arguments.InputObjectTest do
  use Absinthe.Case, async: true

  @schema Absinthe.Fixtures.ArgumentsSchema

  @graphql """
  query ($contact: ContactInput!) {
    user(contact: $contact)
  }
  """
  test "as variable, should work when nested" do
    assert_data(
      %{"user" => "bubba@joe.comasdf"},
      run(
        @graphql,
        @schema,
        variables: %{"contact" => %{"email" => "bubba@joe.com", "contactType" => "Email"}}
      )
    )
  end

  @graphql """
  query ($contact: ContactInput!) {
    user(contact: $contact)
  }
  """
  test "using variables, works in a basic case" do
    assert_data(
      %{"user" => "bubba@joe.comasdf"},
      run(@graphql, @schema, variables: %{"contact" => %{"email" => "bubba@joe.com"}})
    )
  end

  @graphql """
  query ($email: String) {
    contacts(contacts: [{email: $email}, {email: $email}])
  }
  """
  test "using inner variables" do
    assert_data(
      %{"contacts" => ["a@b.com", "a@b.com"]},
      run(@graphql, @schema, variables: %{"email" => "a@b.com"})
    )
  end

  @graphql """
  query ($input: InputStuff!) {
    stuff(stuff: $input)
  }
  """
  test "enforces non_null fields in input passed as variable" do
    assert_error_message_lines(
      [
        ~s(Argument "stuff" has invalid value $input.),
        ~s(In field "nonNullField": Expected type "String!", found null.)
      ],
      run(@graphql, @schema, variables: %{"input" => %{"value" => 5, "nonNullField" => nil}})
    )

    assert_error_message_lines(
      [
        ~s(Argument "stuff" has invalid value $input.),
        ~s(In field "nonNullField": Expected type "String!", found null.)
      ],
      run(@graphql, @schema, variables: %{"input" => %{"value" => 5}})
    )
  end

  @graphql """
  query ($email: String, $defaultWithString: String) {
    user(contact: {email: $email, defaultWithString: $defaultWithString})
  }
  """
  test "can set field default values" do
    assert_data(
      %{"user" => "bubba@joe.comasdf"},
      run(@graphql, @schema, variables: %{"email" => "bubba@joe.com"})
    )
  end

  @graphql """
  query ($email: String) {
    contacts(contacts: [{email: $email}, {email: $email}])
  }
  """
  test "with inner variables, when no variables are given, returns an error" do
    assert_error_message_lines(
      [
        ~s(Argument "contacts" has invalid value [{email: $email}, {email: $email}].),
        ~s(In element #1: Expected type "ContactInput", found {email: $email}.),
        ~s(In field "email": Expected type "String!", found $email.),
        ~s(In element #2: Expected type "ContactInput", found {email: $email}.),
        ~s(In field "email": Expected type "String!", found $email.)
      ],
      run(@graphql, @schema, variables: %{})
    )
  end

  @graphql """
  query {
    user(contact: {email: "bubba@joe.com"})
  }
  """
  test "using literals, works in a basic case" do
    assert_data(%{"user" => "bubba@joe.comasdf"}, run(@graphql, @schema))
  end

  @graphql """
  query {
    testBooleanInputObject(input: {flag: false})
  }
  """
  test "works with inner booleans set to false" do
    # This makes sure we don't accidentally filter out booleans when trying
    # to filter out nils
    assert_data(%{"testBooleanInputObject" => false}, run(@graphql, @schema))
  end

  @graphql """
  query {
    user(contact: {email: "bubba@joe.com", nestedContactInput: {email: "foo"}})
  }
  """
  test "works in a nested case" do
    assert_data(%{"user" => "bubba@joe.comasdf"}, run(@graphql, @schema))
  end

  @graphql """
  query {
    user(contact: {foo: "buz"})
  }
  """
  test "returns the correct error if an inner field is marked non null but is missing" do
    assert_error_message_lines(
      [
        ~s(Argument "contact" has invalid value {foo: "buz"}.),
        ~s(In field "email": Expected type "String!", found null.),
        ~s(In field "foo": Unknown field.)
      ],
      run(@graphql, @schema)
    )
  end

  @graphql """
  query {
    user(contact: {email: "bubba", foo: "buz"})
  }
  """
  test "returns an error if extra fields are given" do
    assert_error_message_lines(
      [
        ~s(Argument "contact" has invalid value {email: "bubba", foo: "buz"}.),
        ~s(In field "foo": Unknown field.)
      ],
      run(@graphql, @schema)
    )
  end

  @graphql """
  query ($contact: ContactInput!) {
    user(contact: $contact)
  }
  """

  test "return field error with suggestion" do
    assert_error_message_lines(
      [
        ~s(Argument "contact" has invalid value $contact.),
        ~s(In field "default_with_stream": Unknown field. Did you mean "default_with_string"?)
      ],
      run(@graphql, @schema,
        variables: %{"contact" => %{"email" => "bubba@joe.com", "default_with_stream" => "asdf"}}
      )
    )
  end

  test "return field error with multiple suggestions" do
    assert_error_message_lines(
      [
        ~s(Argument "contact" has invalid value $contact.),
        ~s(In field "contact_typo": Unknown field. Did you mean "contact_type"?),
        ~s(In field "default_with_stream": Unknown field. Did you mean "default_with_string"?)
      ],
      run(@graphql, @schema,
        variables: %{
          "contact" => %{
            "email" => "bubba@joe.com",
            "default_with_stream" => "asdf",
            "contact_typo" => "foo"
          }
        }
      )
    )
  end

  test "return field error with suggestion for non-null field" do
    assert_error_message_lines(
      [
        ~s(Argument "contact" has invalid value $contact.),
        ~s(In field "email": Expected type "String!", found null.),
        ~s(In field "mail": Unknown field. Did you mean "email"?)
      ],
      run(@graphql, @schema, variables: %{"contact" => %{"mail" => "bubba@joe.com"}})
    )
  end

  @graphql """
  query ($name: String) {
    company(name: $name)
  }
  """
  @tag skip: true
  test "return nil when default_value is nil for simple input" do
    assert_data(
      %{"company" => nil},
      run(
        @graphql,
        @schema,
        variables: %{}
      )
    )
  end

  # TODO: test nil as default for other types
  # TODO: test nil as default for lists
  # TODO: test nil as default for complex objects
end
