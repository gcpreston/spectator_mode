defmodule SpectatorMode.BridgeRelay do
  use GenServer
  alias SpectatorMode.BridgeRegistry

  defstruct bridge_id: nil, subscribers: MapSet.new(), game_metadata: nil

  ## API

  def start_link(bridge_id) do
    GenServer.start_link(__MODULE__, bridge_id,
      name: {:via, Registry, {BridgeRegistry, bridge_id}}
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
  def init(bridge_id) do
    {:ok, %__MODULE__{bridge_id: bridge_id}}
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
end
