defmodule SpectatorMode.StreamIDManager do
  @doc """
  A process to take care of handing out unique stream IDs.

  When a livestream finishes, its ID will be freed to possibly be reassigned.
  """
  use GenServer

  alias SpectatorMode.Streams
  alias SpectatorMode.StreamSignals

  @global_name {:global, __MODULE__}

  ## API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: @global_name)
  end

  @doc """
  Generate a unique stream ID.
  """
  @spec generate_stream_id() :: Streams.stream_id()
  def generate_stream_id do
    GenServer.call(@global_name, :generate_stream_id)
  end

  ## Callbacks

  @impl true
  def init(_) do
    StreamSignals.subscribe()
    {:ok, MapSet.new()}
  end

  @impl true
  def handle_call(:generate_stream_id, _from, state) do
    stream_id = generate_stream_id_helper(state)
    {:reply, stream_id, MapSet.put(state, stream_id)}
  end

  @impl true
  def handle_info({:stream_destroyed, stream_id}, state) do
    {:noreply, MapSet.delete(state, stream_id)}
  end

  ## Helpers

  defp generate_stream_id_helper(unavailable_stream_ids) do
    # random u32
    test_id = Enum.random(0..(2 ** 32 - 1))

    if !MapSet.member?(unavailable_stream_ids, test_id) do
      test_id
    else
      generate_stream_id_helper(unavailable_stream_ids)
    end
  end
end
