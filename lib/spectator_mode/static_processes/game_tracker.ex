defmodule SpectatorMode.GameTracker do
  @moduledoc """
  Track the current game info for each active stream.

  This process owns an ETS table `:livestreams`.
  """
  use GenServer

  alias SpectatorMode.Streams
  alias SpectatorMode.Slp

  @current_games_table_name :livestreams
  @initial_game_state %{fod_platforms: %{left: nil, right: nil}}

  # ETS schema
  # {stream_id(), :event_payloads} => Slp.Events.EventPayloads.t() | nil
  # {stream_id(), :game_start} => Slp.Events.GameStart.t() | nil
  # {stream_id(), :game_state} =>  %{fod_platforms: %{left: Slp.Events.FodPlatforms.t() | nil, right: Slp.Events.FodPlatforms.t() | nil}}
  # {stream_id(), :leftover_buffer} => binary()
  # {stream_id(), :replay} => binary()

  ## API

  def start_link(_) do
    case GenServer.start_link(__MODULE__, [], name: __MODULE__) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Process.link(pid)
        {:ok, pid}

      error ->
        error
    end
  end

  @spec initialize_stream() :: Streams.stream_id()
  def initialize_stream do
    # Generate an unused stream ID.
    # Since this happens in a GenServer call, it is the only message being
    # served at the moment, so there is no risk of the same stream_id being
    # handed out again before the first recipient inserts their keys.

    # TODO: With this no longer being a global process, the stream ID could be
    # defined in a different GameTracker instance. But also not because of :global
    # on PacketHandler. Look into the flow here and refine it.
    stream_id = generate_stream_id()

    insert_helper(stream_id, :event_payloads, nil)
    insert_helper(stream_id, :game_start, nil)
    insert_helper(stream_id, :game_state, @initial_game_state)
    insert_helper(stream_id, :leftover_buffer, <<>>)

    stream_id
  end

  @spec join_payload(Streams.stream_id(), boolean()) :: binary()
  def join_payload(stream_id, return_full_replay) do
    stream_objects =
      :ets.select(@current_games_table_name, [{{{stream_id, :_}, :"$1"}, [], [:"$1"]}])

    event_payloads = Enum.find(stream_objects, fn o -> match?(%Slp.Events.EventPayloads{}, o) end)
    game_start = Enum.find(stream_objects, fn o -> match?(%Slp.Events.GameStart{}, o) end)
    game_state = Enum.find(stream_objects, fn o -> match?(%{fod_platforms: _}, o) end)
    state_stages = if is_nil(game_state), do: [], else: Map.values(game_state[:fod_platforms])

    binary_to_send =
      ([
         event_payloads,
         game_start
       ] ++ state_stages)
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.map(fn e -> e.binary end)
      |> Enum.join()

    binary_to_send
  end

  @doc """
  Asynchronously parse a section of a Slippi stream and execute appropriate
  side-effects. These side effects are specifically (1) updating game state
  being tracked, and (2) sending pubsub notifications about game state changes.

  See the module-level documentation for what information is tracked notified for.
  """
  @spec handle_packet(Streams.stream_id(), binary()) :: :ok
  def handle_packet(stream_id, data) do
    Task.Supervisor.start_child(SpectatorMode.PacketHandleTaskSupervisor, fn ->
      {:ok, maybe_event_payloads} = fetch_event_payloads(stream_id)
      maybe_payload_sizes = get_in(maybe_event_payloads.payload_sizes)
      {:ok, previous_leftover} = fetch_leftover_buffer(stream_id)

      {events, leftover} = Slp.Parser.parse_packet(previous_leftover <> data, maybe_payload_sizes)
      set_leftover_buffer(stream_id, leftover_buffer)
      execute_side_effects(events, stream_id)
    end)

    :ok
  end

  @spec delete(Streams.stream_id()) :: :ok
  def delete(stream_id) do
    for event_type <- [:event_payloads, :game_start, :game_state] do
      :ets.delete(@current_games_table_name, {stream_id, event_type})
    end

    :ok
  end

  @spec list_streams() :: [
          %{stream_id: Streams.stream_id(), active_game: Slp.Events.GameStart.t()}
        ]
  def list_streams do
    :ets.select(
      @current_games_table_name,
      [
        {{{:"$1", :game_start}, :"$2"}, [], [%{stream_id: :"$1", active_game: :"$2"}]}
      ]
    )
  end

  ## Callbacks

  @impl true
  def init(_) do
    :ets.new(@current_games_table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    {:ok, nil}
  end

  ## Helpers

  defp fetch_event_payloads(stream_id) do
    fetch_helper(stream_id, :event_payloads)
  end

  defp fetch_leftover_buffer(stream_id) do
    fetch_helper(stream_id, :leftover_buffer)
  end

  defp set_leftover_buffer(stream_id, leftover_buffer) do
    insert_helper(stream_id, :leftover_buffer, leftover_buffer)
    :ok
  end

  defp set_event_payloads(stream_id, event_payloads) do
    # TODO: Protect against inserting for invalid stream?
    insert_helper(stream_id, :event_payloads, event_payloads)
    :ok
  end

  defp set_game_start(stream_id, game_start) do
    # TODO: Protect against inserting for invalid stream?
    insert_helper(stream_id, :game_start, game_start)
    insert_helper(stream_id, :game_state, @initial_game_state)
    :ok
  end

  defp set_fod_platform(stream_id, side, event) do
    # TODO: Protect against inserting for invalid stream?
    {:ok, current_game_state} = fetch_helper(stream_id, :game_state)
    insert_helper(stream_id, :game_state, put_in(current_game_state, [:fod_platforms, side], event))
    :ok
  end

  defp add_to_replay(Streams.stream_id(), event) do
    {:ok, current_replay} = fetch_helper(stream_id, :replay)
    insert_helper(stream_id, :replay, current_replay <> event.binary)
    :ok
  end

  defp fetch_helper(stream_id, event_type) do
    case :ets.lookup(@current_games_table_name, {stream_id, event_type}) do
      [] -> :error
      [{{^stream_id, ^event_type}, object}] -> {:ok, object}
    end
  end

  defp insert_helper(stream_id, event_type, value) do
    :ets.insert(@current_games_table_name, {{stream_id, event_type}, value})
  end

  defp generate_stream_id do
    # random u32
    test_id = Enum.random(0..(2 ** 32 - 1))

    if !stream_exists?(test_id) do
      test_id
    else
      generate_stream_id()
    end
  end

  defp stream_exists?(stream_id) do
    case :ets.lookup(@current_games_table_name, {stream_id, :game_start}) do
      [] -> false
      _ -> true
    end
  end

  defp execute_side_effects(stream_id, events) do
    Enum.map(events, fn event ->
        add_to_replay(stream_id, event)
        execute_event_side_effects(stream_id, event)
    end)

    :ok
  end

  defp execute_event_side_effects(stream_id, %Slp.Events.GameStart{} = event) do
    set_game_start(stream_id, event)
    # Broadcast parsed event the data; the binary is not needed
    game_settings = Map.put(event, :binary, nil)
    Streams.notify_subscribers(:game_update, {stream_id, game_settings})
  end

  defp execute_event_side_effects(stream_id, %Slp.Events.GameEnd{} = event) do
    set_game_start(stream_id, nil)
    set_event_payloads(stream_id, nil)
    Streams.notify_subscribers(:game_update, {state.stream_id, nil})
  end

  defp execute_event_side_effects(stream_id, %Slp.Events.FodPlatforms{platform: platform} = event) do
    set_fod_platform(stream_id, platform, event)
  end

  defp execute_side_effects(_stream_id, _other_event), do: nil
end
