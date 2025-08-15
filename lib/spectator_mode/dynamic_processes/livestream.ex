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
  alias SpectatorMode.GameTracker

  defstruct stream_id: nil, event_payloads: nil

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

  ## Callbacks

  @impl true
  def init(stream_id) do
    Logger.info("Starting livestream #{stream_id}")
    Streams.notify_subscribers(:livestream_created, stream_id)
    StreamSignals.subscribe(stream_id)

    event_payloads =
      case GameTracker.get_event_payloads(stream_id) do
        {:ok, p} -> p
        :error -> nil
      end

    # PROBLEM
    # Recovering fully from crash in this way basically just means storing all state in ETS.
    # But then when we have that, why store anything in GenServers at all? It feels like
    # redelegating to "solve" a problem, but really you don't solve it you just move it
    # elsewhere and centralize it even more for the possiblity of a bigger failure.
    #
    # To handle subscribers, it could make sense to have them resubscribe upon restart.
    # So to make it work, ViewerSocket processes could also just link this Livestream
    # process and then die with it and re-sub on restart, or something like that.
    #
    # Past that, maybe the rest of the state just belongs in ETS after all. It appears
    # all necessary functions are available on the :ets API to implement gets and sets
    # of the current game info stored in this process' state.
    #
    # The concern would be the ETS owner process crashing, but with it just being a shell
    # for table updates it should be lower risk than Livestream, which has more message types
    # sent and received.
    #
    # And what would need to happen to recover from the ETS owner process crashing and taking
    # the table down with it? That feels like a question for tomorrow
    #
    # --------
    # Why not just make subscriptions work via Phoenix PubSub, and game state work via ETS?

    {:ok, %__MODULE__{stream_id: stream_id, event_payloads: event_payloads}}
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
  def handle_cast({:forward, data}, %{stream_id: stream_id} = state) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      Streams.stream_subtopic(stream_id),
      {:game_data, data}
    )

    {:noreply, update_state_from_game_data(state, data)}
  end

  # TODO: Would like to prefix the event with the module from which it was sent
  #   for clarity between Streams and BridgeSignals (and potential future ones).
  @impl true
  def handle_info({:stream_destroyed, stream_id}, state) do
    GameTracker.delete(stream_id)
    {:stop, :shutdown, state}
  end

  ## Helpers

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

  defp handle_event(%Slp.Events.EventPayloads{} = event, %{stream_id: stream_id} = state) do
    GameTracker.set_event_payloads(stream_id, event)
    put_in(state.event_payloads, event)
  end

  defp handle_event(%Slp.Events.GameStart{} = event, %{stream_id: stream_id} = state) do
    # Store and broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)

    # TODO: Some kind of consolidation here?
    GameTracker.set_game_start(stream_id, event)
    Streams.notify_subscribers(:game_update, {state.stream_id, game_settings})

    state
  end

  defp handle_event(%Slp.Events.GameEnd{}, state) do
    # TODO: Some kind of consolidation here?
    GameTracker.set_game_start(state.stream_id, nil)
    Streams.notify_subscribers(:game_update, {state.stream_id, nil})

    state
  end

  defp handle_event(%Slp.Events.FodPlatforms{binary: _binary, platform: _platform}, state) do
    # TODO
    # put_in(state.current_game_state.fod_platforms[platform], binary)
    state
  end

  defp handle_event(_event, state), do: state
end
