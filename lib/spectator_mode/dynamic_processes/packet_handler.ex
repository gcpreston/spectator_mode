defmodule SpectatorMode.PacketHandler do
  @moduledoc """
  A GenServer to parse packets from a livestream and handle executing
  appropriate side-effects.
  """
  use GenServer, restart: :transient

  require Logger

  alias SpectatorMode.Streams
  alias SpectatorMode.Slp
  alias SpectatorMode.GameTracker
  alias SpectatorMode.Events

  @type t() :: %__MODULE__{
    stream_id: Streams.stream_id(),
    payload_sizes: Events.payload_sizes() | nil,
    replay_so_far: binary() | nil,
    leftover_buffer: binary()
  }

  defstruct stream_id: nil, payload_sizes: nil, replay_so_far: nil, leftover_buffer: <<>>
  # stream_id: Which stream this PacketHandler is managing.
  # payload_sizes: The map of %{command byte => payload size} given at the start
  #   of the current game. A nil value means there is no current game, and that
  #   the next packet processed should be Event Payloads.
  # replay_so_far: The full binary of the current game. A nil value means there
  #   is no current game, just like a nil value of payload_sizes.
  #   TODO: There is a state simplification opportunity here
  # leftover_buffer: If an event binary was split across handle_packet calls,
  #   its start is stored in leftover_buffer. This is then prepended to the next
  #   packet to be processed and reset. Please note that this means packets must
  #   come in order, which is guaranteed by OTP as long as packets are coming
  #   from the same source.

  ## API

  def start_link(opts) do
    stream_id = Keyword.fetch!(opts, :stream_id)
    register_global = Keyword.get(opts, :register_global, false)
    name = if register_global, do: {:global, {__MODULE__, stream_id}}, else: nil

    GenServer.start_link(__MODULE__, stream_id, name: name)
  end

  @spec handle_packet(GenServer.server(), binary()) :: nil
  def handle_packet(server, data) do
    GenServer.cast(server, {:handle_packet, data})
  end

  def get_replay(server) do
    GenServer.call(server, :get_replay)
  end

  ## Callbacks

  @impl true
  def init(stream_id) do
    Logger.info("Starting livestream #{stream_id}")

    payload_sizes =
      case GameTracker.get_event_payloads(stream_id) do
        {:ok, ep} ->
          case ep do
            %Slp.Events.EventPayloads{payload_sizes: ps} -> ps
            _ -> nil
          end

        :error ->
          nil
      end

    {:ok, %__MODULE__{stream_id: stream_id, payload_sizes: payload_sizes}}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Livestream #{state.stream_id} (#{inspect(self())}) terminating, reason: #{inspect(reason)}")
  end

  @impl true
  def handle_cast({:handle_packet, data}, state) do
    maybe_payload_sizes = get_in(state.payload_sizes)

    {events, leftover} = Slp.Parser.parse_packet(state.leftover_buffer <> data, maybe_payload_sizes)

    new_state =
      state
      |> handle_events(events)
      |> maybe_add_to_replay(data)
      |> Map.put(:leftover_buffer, leftover)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_replay, _from, state) do
    {:reply, state.replay_so_far || <<>>, state}
  end

  ## Helpers

  # handle_events/2 and handle_event/2 serve to
  # 1. execute any necessary side-effects based on a Slippi event
  #    (i.e. sending PubSub messages, updating GameTracker)
  # 2. return the modified state based on the event

  defp handle_events(state, events) do
    Enum.reduce(events, state, &handle_event(&1, &2))
  end

  defp handle_event(%Slp.Events.EventPayloads{} = event, %{stream_id: stream_id} = state) do
    GameTracker.set_event_payloads(stream_id, event)
    %{state | payload_sizes: event.payload_sizes, replay_so_far: <<>>}
  end

  defp handle_event(%Slp.Events.GameStart{} = event, %{stream_id: stream_id} = state) do
    # Store and broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)

    GameTracker.set_game_start(stream_id, event)
    Streams.notify_subscribers(:game_update, {state.stream_id, game_settings})

    state
  end

  defp handle_event(%Slp.Events.GameEnd{}, state) do
    GameTracker.set_game_start(state.stream_id, nil)
    GameTracker.set_event_payloads(state.stream_id, nil)
    Streams.notify_subscribers(:game_update, {state.stream_id, nil})

    %{state | payload_sizes: nil, replay_so_far: nil}
  end

  defp handle_event(%Slp.Events.FodPlatforms{platform: platform} = event, state) do
    GameTracker.set_fod_platform(state.stream_id, platform, event)
    state
  end

  defp handle_event(_event, state), do: state

  # Note that with this logic, we never add the game end event to replay_so_far.
  # This is ok though because the point of replay_so_far is to catch up new viewers,
  # rather than save a valid replay to the server.
  defp maybe_add_to_replay(%{replay_so_far: nil} = state, _data), do: state

  defp maybe_add_to_replay(%{replay_so_far: replay_so_far} = state, data) do
    %{state | replay_so_far: replay_so_far <> data}
  end
end
