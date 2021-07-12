defmodule Absinthe.Resolution.Helpers do
  @moduledoc """
  Handy functions for returning async or batched resolution functions

  Using `Absinthe.Schema.Notation` or (by extension) `Absinthe.Schema` will
  automatically import the `batch` and `async` helpers. Dataloader helpers
  require an explicit `import Absinthe.Resolution.Helpers` invocation, since
  dataloader is an optional dependency.
  """

  alias Absinthe.Middleware

  @doc """
  Execute resolution field asynchronously.

  This is a helper function for using the `Absinthe.Middleware.Async`.

  Forbidden in mutation fields. (TODO: actually enforce this)

  ## Options
     - `:timeout` default: `30_000`. The maximum timeout to wait for running
     the task.

  ## Example

  Using the `Absinthe.Resolution.Helpers.async/1` helper function:
  ```elixir
  field :time_consuming, :thing do
    resolve fn _, _, _ ->
      async(fn ->
        {:ok, long_time_consuming_function()}
      end)
    end
  end
  ```
  """
  @spec async((() -> term)) :: {:middleware, Middleware.Async, term}
  @spec async((() -> term), opts :: [{:timeout, pos_integer}]) ::
          {:middleware, Middleware.Async, term}
  def async(fun, opts \\ []) do
    {:middleware, Middleware.Async, {fun, opts}}
  end

  @doc """
  Batch the resolution of several functions together.

  Helper function for creating `Absinthe.Middleware.Batch`

  ## Options
    - `:timeout` default: `5_000`. The maximum timeout to wait for running
    a batch.

  ## Example

  Raw usage:
  ```elixir
  object :post do
    field :name, :string
    field :author, :user do
      resolve fn post, _, _ ->
        batch({__MODULE__, :users_by_id}, post.author_id, fn batch_results ->
          {:ok, Map.get(batch_results, post.author_id)}
        end)
      end
    end
  end

  def users_by_id(_, user_ids) do
    users = Repo.all from u in User, where: u.id in ^user_ids
    Map.new(users, fn user -> {user.id, user} end)
  end
  ```
  """
  @spec batch(Middleware.Batch.batch_fun(), term, Middleware.Batch.post_batch_fun()) ::
          {:middleware, Middleware.Batch, term}
  @spec batch(
          Middleware.Batch.batch_fun(),
          term,
          Middleware.Batch.post_batch_fun(),
          opts :: [{:timeout, pos_integer}]
        ) :: {:middleware, Middleware.Batch, term}
  def batch(batch_fun, batch_data, post_batch_fun, opts \\ []) do
    batch_config = {batch_fun, batch_data, post_batch_fun, opts}
    {:middleware, Middleware.Batch, batch_config}
  end

  if Code.ensure_loaded?(Dataloader) do
    @doc """
    Dataloader helper function

    This function is not imported by default. To make it available in your module do

    ```
    import Absinthe.Resolution.Helpers
    ```

    This function helps you use data loader in a direct way within your schema.
    While normally the `dataloader/1,2,3` helpers are enough, `on_load/2` is useful
    when you want to load multiple things in a single resolver, or when you need
    fine grained control over the dataloader cache.

    ## Examples

    ```elixir
    field :reports, list_of(:report) do
      resolve fn shipment, _, %{context: %{loader: loader}} ->
        loader
        |> Dataloader.load(SourceName, :automatic_reports, shipment)
        |> Dataloader.load(SourceName, :manual_reports, shipment)
        |> on_load(fn loader ->
          reports =
            loader
            |> Dataloader.get(SourceName, :automatic_reports, shipment)
            |> Enum.concat(Dataloader.get(loader, SourceName, :manual_reports, shipment))
            |> Enum.sort_by(&reported_at/1)
          {:ok, reports}
        end)
      end
    end
    ```
    """
    def on_load(loader, fun) do
      {:middleware, Absinthe.Middleware.Dataloader, {loader, fun}}
    end

    @type dataloader_tuple :: {:middleware, Absinthe.Middleware.Dataloader, term}
    @type dataloader_key_fun ::
            (Absinthe.Resolution.source(),
             Absinthe.Resolution.arguments(),
             Absinthe.Resolution.t() ->
               {any, map})
    @type dataloader_opt ::
            {:args, map}
            | {:use_parent, true | false}
            | {:callback, (map(), map(), map() -> any())}

    @doc """
    Resolve a field with a dataloader source.

    This function is not imported by default. To make it available in your module do

    ```
    import Absinthe.Resolution.Helpers
    ```

    Same as `dataloader/3`, but it infers the resource name from the field name.

    ## Examples

    ```
    field :author, :user, resolve: dataloader(Blog)
    ```

    This is identical to doing the following.

    ```
    field :author, :user, resolve: dataloader(Blog, :author, [])
    ```
    """
    @spec dataloader(Dataloader.source_name()) :: dataloader_key_fun()
    def dataloader(source) do
      dataloader(source, [])
    end

    @doc """
    Resolve a field with a dataloader source.

    This function is not imported by default. To make it available in your module do

    ```
    import Absinthe.Resolution.Helpers
    ```

    Same as `dataloader/3`, but it infers the resource name from the field name. For `opts` see
    `dataloader/3` on what options can be passed in.

    ## Examples

    ```
    object :user do
      field :posts, list_of(:post),
        resolve: dataloader(Blog, args: %{deleted: false})

      field :organization, :organization do
        resolve dataloader(Accounts, use_parent: false)
      end

      field(:account_active, non_null(:boolean), resolve: dataloader(
          Accounts, callback: fn account, _parent, _args ->
            {:ok, account.active}
          end
        )
      )
    end
    ```

    """
    @dialyzer {:no_contracts, dataloader: 2}
    @spec dataloader(Dataloader.source_name(), [dataloader_opt]) :: dataloader_key_fun()
    def dataloader(source, opts) when is_list(opts) do
      fn parent, args, %{context: %{loader: loader}} = res ->
        resource = res.definition.schema_node.identifier
        do_dataloader(loader, source, {resource, args}, parent, opts)
      end
    end

    @doc """
    Resolve a field with Dataloader

    This function is not imported by default. To make it available in your module do

    ```
    import Absinthe.Resolution.Helpers
    ```

    While `on_load/2` makes using dataloader directly easy within a resolver function,
    it is often unnecessary to need this level of direct control.

    The `dataloader/3` function exists to provide a simple API for using dataloader.
    It takes the name of a data source, the name of the resource you want to load,
    and then a variety of options.

    ## Basic Usage

    ```
    object :user do
      field :posts, list_of(:post),
        resolve: dataloader(Blog, :posts, args: %{deleted: false})

      field :organization, :organization do
        resolve dataloader(Accounts, :organization, use_parent: false)
      end

      field(:account_active, non_null(:boolean), resolve: dataloader(
          Accounts, :account, callback: fn account, _parent, _args ->
            {:ok, account.active}
          end
        )
      )
    end
    ```

    ## Key Functions

    Instead of passing in a literal like `:posts` or `:organization` in as the resource,
    it is also possible pass in a function:

    ```
    object :user do
      field :posts, list_of(:post) do
        arg :limit, non_null(:integer)
        resolve dataloader(Blog, fn user, args, info ->
          args = Map.update!(args, :limit, fn val ->
            max(min(val, 20), 0)
          end)
          {:posts, args}
        end)
      end
    end
    ```

    In this case we want to make sure that the limit value cannot be larger than
    `20`. By passing a callback function to `dataloader/2` we can ensure that
    the value will fall nicely between 0 and 20.

    If you have defined a
    [custom batch query](https://hexdocs.pm/dataloader/Dataloader.Ecto.html#module-custom-batch-queries),
    you can instead return a `Map` with `:batch` key to specify the `batch_key` of `Dataloader.load/4` /
    `Dataloader.get/4` and an `:item` key to specify `item_key` argument of `Dataloader.get/4`.

    ```
    # ...
    resolve dataloader(Posts, fn user, _args, _info ->
      %{batch: {{:one, Post}, %{}}, item: [post_count: user]}
    end)
    # ...
    ```

    ## Options

    - `:args` default: `%{}`. Any arguments you want to always pass into the
    `Dataloader.load/4` call. Resolver arguments are merged into this value and,
    in the event of a conflict, the resolver arguments win.
    - `:callback` default: return result wrapped in ok or error tuple.
    Callback that is run with result of dataloader. It receives the result as
    the first argument, and the parent and args as second and third. Can be used
    to e.g. compute fields on the return value of the loader. Should return an
    ok or error tuple.
    - `:use_parent` default: `false`. This option affects whether or not the `dataloader/2`
    helper will use any pre-existing value on the parent. IE if you return
    `%{author: %User{...}}` from a blog post the helper will by default simply use
    the pre-existing author. Set it to true if you want to opt into using the
    pre-existing value instead of loading it fresh.

    Ultimately, this helper calls `Dataloader.load/4`
    using the loader in your context, the source you provide, the tuple `{resource, args}`
    as the batch key, and then the parent value of the field

    ```
    def dataloader(source_name, resource) do
      fn parent, args, %{context: %{loader: loader}} ->
        args = Map.merge(opts[:args] || %{}, args)
        loader
        |> Dataloader.load(source_name, {resource, args}, parent)
        |> on_load(fn loader ->
          {:ok, Dataloader.get(loader, source_name, {resource, args}, parent)}
        end)
      end
    end
    ```

    """
    def dataloader(source, fun, opts \\ [])

    @spec dataloader(Dataloader.source_name(), any) :: dataloader_key_fun
    @spec dataloader(Dataloader.source_name(), dataloader_key_fun | any, [dataloader_opt]) ::
            dataloader_key_fun
    def dataloader(source, fun, opts) when is_function(fun, 3) do
      fn parent, args, %{context: %{loader: loader}} = res ->
        {batch_key, parent} =
          case fun.(parent, args, res) do
            {resource, args} -> {{resource, args}, parent}
            %{batch: batch, item: item} -> {batch, item}
          end

        do_dataloader(loader, source, batch_key, parent, opts)
      end
    end

    def dataloader(source, resource, opts) do
      fn parent, args, %{context: %{loader: loader}} ->
        do_dataloader(loader, source, {resource, args}, parent, opts)
      end
    end

    defp use_parent(loader, source, batch_key, parent, opts) when is_map(parent) do
      resource =
        case batch_key do
          {_cardinality, resource, _args} -> resource
          {resource, _args} -> resource
        end

      with true <- Keyword.get(opts, :use_parent, false),
           {:ok, val} <- Map.fetch(parent, resource) do
        Dataloader.put(loader, source, batch_key, parent, val)
      else
        _ -> loader
      end
    end

    defp use_parent(loader, _source, _batch_key, _parent, _opts), do: loader

    defp do_dataloader(loader, source, batch_key, parent, opts) do
      args_from_opts = Keyword.get(opts, :args, %{})

      {batch_key, args} =
        case batch_key do
          {cardinality, resource, args} ->
            args = Map.merge(args_from_opts, args)
            {{cardinality, resource, args}, args}

          {resource, args} ->
            args = Map.merge(args_from_opts, args)
            {{resource, args}, args}
        end

      loader
      |> use_parent(source, batch_key, parent, opts)
      |> Dataloader.load(source, batch_key, parent)
      |> on_load(fn loader ->
        callback = Keyword.get(opts, :callback, default_callback(loader))

        loader
        |> Dataloader.get(source, batch_key, parent)
        |> callback.(parent, args)
      end)
    end

    defp default_callback(%{options: loader_options}) do
      if loader_options[:get_policy] == :tuples do
        fn result, _parent, _args -> result end
      else
        fn result, _parent, _args -> {:ok, result} end
      end
    end
  end
end
