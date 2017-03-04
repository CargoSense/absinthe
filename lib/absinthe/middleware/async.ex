defmodule Absinthe.Middleware.Async do
  @moduledoc """
  This plugin enables asynchronous execution of a field.

  See also `Absinthe.Resolution.Helpers.async/1`

  # Example Usage:

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

  Using the bare plugin API
  ```elixir
  field :time_consuming, :thing do
    resolve fn _, _, _ ->
      task = Task.async(fn ->
        {:ok, long_time_consuming_function()}
      end
      {:middleware, #{__MODULE__}, task}
    end
  end
  ```

  This module also serves as an example for how to build middleware that uses the
  resolution callbacks.

  See the source code and associated comments for further details.
  """

  @behaviour Absinthe.Middleware

  # A function has handed resolution off to this middleware. The first argument
  # is the current resolution struct. The `task_data` argument already includes
  # the task.
  #
  # This function suspends resolution, and sets the async flag true in the resolution
  # accumulator. This will be used later to determine that we need to run resolution
  # again.
  #
  # Finally, this function inserts additional middleware into the remaining middleware
  # stack for this field. On the next resolution pass, we need to `Task.await` the
  # task so we have actual data. Thus, we prepend this module to the middleware stack.
  # The resolution struct will be suspend, and thus is handled by the second clause of
  # this function.
  def call(%{state: :cont} = res, task_data) do
    %{res |
      state: :suspend,
      acc: Map.put(res.acc, __MODULE__, true),
      middleware: [Absinthe.Middleware.plug(__MODULE__, task_data) | res.middleware]
    }
  end

  # This is the clause that gets called on the second pass. There's very little
  # to do here. We just need to await the task started in the previous pass.
  #
  # We also need to set the `state` to `:cont` so that resolution will continue.
  #
  # Finally, we apply the result to the resolution using a helper function that ensures
  # we handle the different tuple results
  def call(%{state: :suspend} = res, {task, opts}) do
    result = Task.await(task, opts[:timeout] || 30_000)

    %{res | state: :halt}
    |> Absinthe.Resolution.put_result(result)
  end

  # We must set the flag to false because if a previous resolution iteration
  # set it to true it needs to go back to false now. It will be set
  # back to true if any field uses this plugin again.
  def before_resolution(acc) do
    Map.put(acc, __MODULE__, false)
  end
  # Nothing to do after resolution for this plugin, so we no-op
  def after_resolution(acc), do: acc

  # If the flag is set we need to do another resolution phase.
  # otherwise, we do not
  def pipeline(pipeline, acc) do
    case acc do
      %{__MODULE__ => true} ->
        [Absinthe.Middleware.resolution_phases | pipeline]
      _ ->
        pipeline
    end
  end
end
