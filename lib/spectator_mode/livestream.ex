defmodule SpectatorMode.Livestream do
  @moduledoc """
  A process to represent a Slippi stream. This process serves to receive data
  from a provider and to forward it to clients.
  """
  use GenServer, restart: :transient

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.StreamSignals
  alias SpectatorMode.Slp
  alias SpectatorMode.LivestreamRegistry

  defstruct stream_id: nil,
            subscribers: MapSet.new(),
            event_payloads: nil,
            current_game_start: nil,
            current_game_state: %{fod_platforms: %{left: nil, right: nil}}

  # :current_game_start stores the parsed GameStart event for the current game.
  # :current_game_state stores the ensemble of stateful information which may
  #   be needed to properly render the game and may change over time.
  #   Specifically, it stores the binary version of the latest event affecting
  #   each different part of the game state, if one has been received.

  defmodule LivestreamRegistryValue do
    defstruct active_game: nil
  end

  ## API

  def start_link(stream_id) do
    GenServer.start_link(__MODULE__, stream_id,
      name: {:via, Registry, {SpectatorMode.LivestreamRegistry, stream_id, %LivestreamRegistryValue{}}}
    )
  end

  @doc """
  Forward binary data to all subscribing processes.

  Data is delivered as a message: `{:game_data, binary()}`.
  """
  @spec forward(GenServer.server(), binary()) :: nil
  def forward(server, data) do
    GenServer.cast(server, {:forward, data})
  end

  @doc """
  Subscribe the calling process to receive data from this livestream.
  """
  @spec subscribe(GenServer.server()) :: {:ok, binary()}
  def subscribe(server) do
    GenServer.call(server, :subscribe)
  end

  ## Callbacks

  @impl true
  def init(stream_id) do
    Logger.info("Starting livestream #{stream_id}")
    Streams.notify_subscribers(:livestream_created, stream_id)
    StreamSignals.subscribe(stream_id)
    Process.send_after(self(), :crash, 8000)
    {:ok, %__MODULE__{stream_id: stream_id}}
  end

  @impl true
  def terminate(reason, state) do
    # Notify subscribers on normal shutdowns. The possibility of this
    # callback not being invoked in a crash is not concerning, because
    # any such crash would invoke a restart from the supervisor.
    Logger.info("Livestream #{state.stream_id} (#{inspect(self())}) terminating, reason: #{inspect(reason)}")
    Streams.notify_subscribers(:livestream_destroyed, state.stream_id)
  end

  @impl true
  def handle_call(:subscribe, {from_pid, _tag}, %{subscribers: subscribers} = state) do
    binary_to_send =
      [
        get_in(state.event_payloads.binary),
        get_in(state.current_game_start.binary),
        get_in(state.current_game_state.fod_platforms.left),
        get_in(state.current_game_state.fod_platforms.right)
      ]
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.join()

    {:reply, binary_to_send, %{state | subscribers: MapSet.put(subscribers, from_pid)}}
  end

  @impl true
  def handle_cast({:forward, data}, %{subscribers: subscribers} = state) do
    # TODO: This feels like it could just be a pubsub broadcast
    for subscriber_pid <- subscribers do
      send(subscriber_pid, {:game_data, data})
    end

    {:noreply, update_state_from_game_data(state, data)}
  end

  # TODO: Would like to prefix the event with the module from which it was sent
  #   for clarity between Streams and BridgeSignals (and potential future ones).
  @impl true
  def handle_info({:stream_destroyed, _bridge_id}, state) do
    {:stop, :shutdown, state}
  end

  ## Helpers

  defp update_registry_value(stream_id, updater) do
    Registry.update_value(LivestreamRegistry, stream_id, updater)
  end

  defp update_state_from_game_data(state, data) do
    maybe_payload_sizes = get_in(state.event_payloads.payload_sizes)
    events = Slp.Parser.parse_packet(data, maybe_payload_sizes)
    handle_events(events, state)
  end

  # handle_events/2 and handle_event/2 serve to
  # 1. execute any necessary side-effects based on a Slippi event
  #    (i.e. sending PubSub messages)
  # 2. return the modified state based on the event

  defp handle_events(events, state) do
    Enum.reduce(events, state, &handle_event(&1, &2))
  end

  defp handle_event(%Slp.Events.EventPayloads{} = event, state) do
    new_state = put_in(state.event_payloads, event)
    put_in(new_state.current_game_start, nil)
  end

  defp handle_event(%Slp.Events.GameStart{} = event, state) do
    # Store and broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)

    update_registry_value(state.stream_id, fn value ->
      put_in(value.active_game, game_settings)
    end)

    Streams.notify_subscribers(:game_update, {state.stream_id, game_settings})

    put_in(state.current_game_start, event)
  end

  defp handle_event(%Slp.Events.GameEnd{}, state) do
    update_registry_value(state.stream_id, fn value -> put_in(value.active_game, nil) end)
    Streams.notify_subscribers(:game_update, {state.stream_id, nil})

    state
  end

  defp handle_event(%Slp.Events.FodPlatforms{binary: binary, platform: platform}, state) do
    put_in(state.current_game_state.fod_platforms[platform], binary)
  end

  defp handle_event(_event, state), do: state
end
