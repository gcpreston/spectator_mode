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
  defstruct [
    bridge_id: nil,
    subscribers: MapSet.new(),
    events: %{
      event_payloads: nil,
      game_start: nil
    },
    new_viewer_packet: nil
  ]

  # :events stores structs found in `SpectatorMode.Slp.Events` which are
  #   relevant to the current game.
  # :new_viewer_packet is the binary to send to new viewers upon connection.
  #   This will contain the Event Payloads and Game Start events, once both
  #   are available.

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
    notify_subscribers(:relay_destroyed, state.bridge_id)
  end

  @impl true
  def handle_info({:EXIT, _peer_pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_call(:subscribe, {from_pid, _tag}, %{subscribers: subscribers} = state) do
    {:reply, state.new_viewer_packet, %{state | subscribers: MapSet.put(subscribers, from_pid)}}
  end

  @impl true
  def handle_cast({:forward, data}, %{subscribers: subscribers} = state) do
    payload_sizes = if state.events.event_payloads, do: state.events.event_payloads.payload_sizes, else: nil
    events = Slp.Parser.parse_packet(data, payload_sizes)
    new_state = handle_events(events, state)

    for subscriber_pid <- subscribers do
      send(subscriber_pid, {:game_data, data})
    end

    {:noreply, new_state}
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

  # handle_events/2 and handle_event/2 serve to
  # 1. execute any necessary side-effects based on a Slippi event
  #    (i.e. sending PubSub messages)
  # 2. return the modified state based on the event

  defp handle_events(events, state) do
    Enum.reduce(events, state, &(handle_event(&1, &2)))
  end

  defp handle_event(%Slp.Events.EventPayloads{} = event, state) do
    put_in(state.events.event_payloads, event)
  end

  defp handle_event(%Slp.Events.GameStart{} = event, state) do
    # Store and broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)
    update_registry_value(state.bridge_id, game_settings)
    notify_subscribers(:game_update, {state.bridge_id, game_settings})

    new_state = put_in(state.events.game_start, event)

    if state.events.event_payloads do
      new_viewer_packet = new_state.events.event_payloads.binary <> new_state.events.game_start.binary
      put_in(new_state.new_viewer_packet, new_viewer_packet)
    else
      new_state
    end
  end

  defp handle_event(%Slp.Events.GameEnd{}, state) do
    update_registry_value(state.bridge_id, nil)
    notify_subscribers(:game_update, {state.bridge_id, nil})

    new_state = put_in(state.events.game_start, nil)
    # Event Payloads is re-sent on next game start, so it will be forwarded then.
    put_in(new_state.new_viewer_packet, nil)
  end

  defp handle_event(_event, state), do: state
end
