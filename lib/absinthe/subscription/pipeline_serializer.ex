defmodule Absinthe.Subscription.PipelineSerializer do
  @moduledoc """
  Serializer responsible for packing and unpacking pipeline stored in the Elixir registry.

  The purpose of this logic is saving memory by deduplicating repeating options - (ETS
  backed registry stores them flat in the memory).

  It also strips the context out of the options list. This value needs to be
  re-populated from another key.
  """

  alias Absinthe.{Phase, Pipeline}

  @type options_label :: {:options, non_neg_integer()}

  @type packed_phase_config :: Phase.t() | {Phase.t(), options_label()}

  @type options_map :: %{options_label() => Keyword.t()}

  @type packed_pipeline :: {:packed, [packed_phase_config()], options_map()}

  @spec pack(Pipeline.t()) :: packed_pipeline()
  def pack(pipeline) do
    {packed_pipeline, options_reverse_map} =
      pipeline
      |> List.flatten()
      |> Enum.map(&remove_context/1)
      |> Enum.map_reduce(%{}, &maybe_pack_phase/2)

    options_map =
      Map.new(options_reverse_map, fn {options, label} ->
        {label, options}
      end)

    {:packed, packed_pipeline, options_map}
  end

  @spec unpack(Pipeline.t() | packed_pipeline()) :: Pipeline.t()
  def unpack({:packed, pipeline, options_map}) do
    Enum.map(pipeline, fn
      {phase, {:options, _n} = options_label} ->
        {phase, Map.fetch!(options_map, options_label)}

      phase ->
        phase
    end)
  end

  def unpack([_ | _] = pipeline) do
    pipeline
  end

  defp remove_context({phase, opts}) do
    {phase, Keyword.delete(opts, :context)}
  end

  defp remove_context(phase) do
    phase
  end

  defp maybe_pack_phase({phase, options}, options_reverse_map) do
    if Map.has_key?(options_reverse_map, options) do
      options_label = options_reverse_map[options]

      {{phase, options_label}, options_reverse_map}
    else
      new_index = map_size(options_reverse_map)
      options_label = {:options, new_index}
      options_reverse_map = Map.put(options_reverse_map, options, options_label)

      {{phase, options_label}, options_reverse_map}
    end
  end

  defp maybe_pack_phase(phase, options_reverse_map) do
    {phase, options_reverse_map}
  end
end
