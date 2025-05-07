defmodule SpectatorMode.BridgeRelay do
  use GenServer, restart: :temporary
  # Use temporary restart while client closes on WebSocket error. Once the
  # client is made to be more fault tolerant and can stay open, this can
  # be transient.

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorMode.Slp
  alias SpectatorMode.BridgeRegistry

  @enforce_keys [:bridge_id]
  defstruct bridge_id: nil,
            subscribers: MapSet.new(),
            payload_sizes: nil,
            current_game_start: nil,
            current_game_packets: []

  # :current_game_start stores the parsed GameStart event for the current game.
  # :current_game_packets stores all the packets of the current game, which are
  #   sent to new viewers upon join.

  ## API

  def start_link({bridge_id, source_pid}) do
    GenServer.start_link(__MODULE__, {bridge_id, source_pid},
      name: {:via, Registry, {SpectatorMode.BridgeRegistry, bridge_id}}
    )
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
    Logger.info("Starting bridge relay #{bridge_id}")
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
    Logger.info("Relay #{state.bridge_id} terminating, reason: #{inspect(reason)}")

    if reason == :bridge_quit do
      notify_subscribers(:relay_destroyed, state.bridge_id)
    else
      notify_subscribers(:relay_disconnected, state.bridge_id)
    end
  end

  @impl true
  def handle_info({:EXIT, _peer_pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_call(:subscribe, {from_pid, _tag}, %{subscribers: subscribers} = state) do
    {:reply, state.current_game_packets |> Enum.reverse() |> Enum.join(),
     %{state | subscribers: MapSet.put(subscribers, from_pid)}}
  end

  @impl true
  def handle_cast({:forward, data}, %{subscribers: subscribers} = state) do
    for subscriber_pid <- subscribers do
      send(subscriber_pid, {:game_data, data})
    end

    {:noreply, update_state_from_game_data(state, data)}
  end

  ## Helpers

  defp notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      Streams.index_subtopic(),
      {event, result}
    )
  end

  defp update_registry_value(bridge_id, new_value) do
    Registry.update_value(BridgeRegistry, bridge_id, fn _old_value -> new_value end)
  end

  defp update_state_from_game_data(state, data) do
    maybe_payload_sizes = state.payload_sizes
    events = Slp.Parser.parse_packet(data, maybe_payload_sizes)
    new_state = handle_events(events, state)
    update_in(new_state.current_game_packets, &[data | &1])
  end

  # handle_events/2 and handle_event/2 serve to
  # 1. execute any necessary side-effects based on a Slippi event
  #    (i.e. sending PubSub messages)
  # 2. return the modified state based on the event

  defp handle_events(events, state) do
    Enum.reduce(events, state, &handle_event(&1, &2))
  end

  defp handle_event(%Slp.Events.EventPayloads{} = event, state) do
    new_state = put_in(state.payload_sizes, event.payload_sizes)
    put_in(new_state.current_game_start, nil)
  end

  defp handle_event(%Slp.Events.GameStart{} = event, state) do
    # Store and broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)
    update_registry_value(state.bridge_id, game_settings)
    notify_subscribers(:game_update, {state.bridge_id, game_settings})

    put_in(state.current_game_start, event)
  end

  defp handle_event(%Slp.Events.GameEnd{}, state) do
    update_registry_value(state.bridge_id, nil)
    notify_subscribers(:game_update, {state.bridge_id, nil})

    state
  end

  defp handle_event(_event, state), do: state
end
