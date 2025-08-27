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

  defstruct stream_id: nil, payload_sizes: nil, replay_so_far: nil

  ## API

  def start_link(stream_id) do
    GenServer.start_link(__MODULE__, stream_id,
      name: {:via, Registry, {SpectatorMode.PacketHandlerRegistry, stream_id}}
    )
  end

  @spec handle_packet(GenServer.server(), binary()) :: nil
  def handle_packet(server, data) do
    GenServer.cast(server, {:handle_packet, data})
  end

  @spec get_replay(GenServer.server(), pos_integer()) :: binary()
  def get_replay(server, bytes_start) do
    GenServer.call(server, {:get_replay, bytes_start})
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
    events = Slp.Parser.parse_packet(data, maybe_payload_sizes)
    new_state = handle_events(events, state)
    new_state = %{new_state | replay_so_far: new_state.replay_so_far <> data}

    {:noreply, new_state}
  end

  # TODO: Alright yeah this is inevitably gonna cause issues if there are many people
  #   spectating via dolphin at once. This would be better in ETS for read concurrency,
  #   but then writing would still be a bottleneck...
  #
  # Don't worry about this for now though because ideally this will be implemented using
  # slippi-launcher main rather than sharlot's fork. Just for this proof of concept hack.
  @impl true
  def handle_call({:get_replay, bytes_start}, _from, state) do
    <<_::binary-size(bytes_start), rest>> = state.replay_so_far
    {:reply, rest, state}
  end

  ## Helpers

  # handle_events/2 and handle_event/2 serve to
  # 1. execute any necessary side-effects based on a Slippi event
  #    (i.e. sending PubSub messages, updating GameTracker)
  # 2. return the modified state based on the event

  defp handle_events(events, state) do
    Enum.reduce(events, state, &handle_event(&1, &2))
  end

  defp handle_event(%Slp.Events.EventPayloads{} = event, %{stream_id: stream_id} = state) do
    # Initialize stored replay
    # new_state = %{state | replay_so_far: <<0x7b, 0x55, 0x03, 0x72, 0x61, 0x77, 0x5b, 0x24, 0x55, 0x23, 0x6c, 0x00>>}
    new_state = %{state | replay_so_far: <<>>}
    GameTracker.set_event_payloads(stream_id, event)
    put_in(new_state.payload_sizes, event.payload_sizes)
  end

  defp handle_event(%Slp.Events.GameStart{} = event, %{stream_id: stream_id} = state) do
      IO.puts("Set game start for stream #{inspect(stream_id)}")
    # Store and broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)

    GameTracker.set_game_start(stream_id, event)
    Streams.notify_subscribers(:game_update, {state.stream_id, game_settings})

    state
  end

  defp handle_event(%Slp.Events.GameEnd{}, state) do
    IO.puts("Set game end for stream #{inspect(state.stream_id)}")
    GameTracker.set_game_start(state.stream_id, nil)
    Streams.notify_subscribers(:game_update, {state.stream_id, nil})

    state
  end

  defp handle_event(%Slp.Events.FodPlatforms{platform: platform} = event, state) do
    GameTracker.set_fod_platform(state.stream_id, platform, event)
    state
  end

  defp handle_event(_event, state), do: state
end
