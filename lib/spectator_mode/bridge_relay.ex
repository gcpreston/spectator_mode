defmodule SpectatorMode.BridgeRelay do
  use GenServer
  alias SpectatorMode.BridgeRegistry
  alias SpectatorMode.StreamsManager

  defstruct bridge_id: nil, subscribers: MapSet.new(), game_metadata: nil

  ## API

  # TODO: optional name pass
  # TODO: call StreamsManager after initialization to
  #   set up monitoring. This allows monitoring to be
  #   set on crash restart, outside of the :start_relay flow
  #   - also look into module-based dynamicsupervisor for this
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
    {:ok, %__MODULE__{bridge_id: bridge_id}, {:continue, :notify_streams_manager}}
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

  @impl true
  def handle_continue(:notify_streams_manager, state) do
    StreamsManager.start_monitor(state.bridge_id)
    {:noreply, state}
  end
end
