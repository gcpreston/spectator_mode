defmodule SpectatorMode.BridgeRelay do
  use GenServer, restart: :transient

  require Logger
  alias SpectatorMode.Streams

  defstruct bridge_id: nil, subscribers: MapSet.new(), game_metadata: nil

  ## API

  def start_link({bridge_id, source_pid}) do
    GenServer.start_link(__MODULE__, {bridge_id, source_pid},
      name: {:via, Registry, {SpectatorMode.BridgeRegistry, bridge_id}}
    )
  end

  def set_metadata(bridge, data) do
    GenServer.call(bridge, {:set_metadata, data})
  end

  def forward(bridge, data) do
    GenServer.cast(bridge, {:forward, data})
  end

  def subscribe(bridge) do
    GenServer.call(bridge, :subscribe)
  end

  ## Callbacks

  @impl true
  def init({bridge_id, source_pid}) do
    IO.inspect(bridge_id, label: "Starting bridge relay:")
    Process.link(source_pid)
    Process.flag(:trap_exit, true)
    notify_subscribers(:relay_created, bridge_id)
    {:ok, %__MODULE__{bridge_id: bridge_id}}
  end

  @impl true
  def terminate(reason, state) do
    # Notify subscribers on normal shutdowns. The possibility of this
    # callback not being invoked in a crash is not concerning, because
    # any such crash would invoke a restart from the supervisor.
    Logger.debug("Relay #{state.bridge_id} terminating, reason: #{inspect(reason)}")
    notify_subscribers(:relay_destroyed, state.bridge_id)
  end

  @impl true
  def handle_info({:EXIT, _peer_pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_call(:subscribe, {from_pid, _tag}, %{subscribers: subscribers} = state) do
    {:reply, state.game_metadata, %{state | subscribers: MapSet.put(subscribers, from_pid)}}
  end

  def handle_call({:set_metadata, data}, _from, state) do
    {:reply, :ok, %{state | game_metadata: data}}
  end

  @impl true
  def handle_cast({:forward, data}, %{subscribers: subscribers} = state) do
    for subscriber_pid <- subscribers do
      send(subscriber_pid, {:game_data, data})
    end

    {:noreply, state}
  end

  ## Helpers

  defp notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      Streams.index_subtopic(),
      {event, result}
    )
  end
end
