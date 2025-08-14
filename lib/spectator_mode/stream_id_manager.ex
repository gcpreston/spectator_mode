defmodule SpectatorMode.StreamIDManager do
  @doc """
  A process to take care of handing out unique stream IDs.

  This process owns an ETS table named `:stream_ids`.
  """
  use GenServer

  alias SpectatorMode.Streams
  alias SpectatorMode.StreamSignals

  @stream_ids_table_name :stream_ids

  ## API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: {:global, __MODULE__})
  end

  @doc """
  Generate a unique stream ID.
  """
  @spec generate_stream_id() :: Streams.stream_id()
  def generate_stream_id do
    GenServer.call({:global, __MODULE__}, :generate_stream_id)
  end

  ## Callbacks

  @impl true
  def init(_) do
    :ets.new(@stream_ids_table_name, [:set, :protected, :named_table])
    StreamSignals.subscribe()

    {:ok, nil}
  end

  @impl true
  def handle_call(:generate_stream_id, _from, state) do
    {:reply, generate_stream_id_helper(), state}
  end

  @impl true
  def handle_info({:stream_destroyed, stream_id}, state) do
    :ets.delete(@stream_ids_table_name, stream_id)
    {:noreply, state}
  end

  ## Helpers

  defp generate_stream_id_helper do
    # random u8
    test_id = Enum.random(0..(2 ** 32 - 1))

    if :ets.insert_new(@stream_ids_table_name, {test_id, true}) do
      test_id
    else
      generate_stream_id_helper()
    end
  end
end
