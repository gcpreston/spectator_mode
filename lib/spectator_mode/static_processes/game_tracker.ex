defmodule SpectatorMode.GameTracker do
  @moduledoc """
  Track the current game info for each active stream.

  This process owns an ETS table `:livestreams`.
  """
  use GenServer

  alias SpectatorMode.Streams
  alias SpectatorMode.Slp

  @current_games_table_name :livestreams
  @global_name {:global, __MODULE__}
  @initial_game_state %{fod_platforms: %{left: nil, right: nil}}

  # ETS schema
  # {stream_id(), :event_payloads} => Slp.Events.EventPayloads.t() | nil
  # {stream_id(), :game_start} => Slp.Events.GameStart.t() | nil
  # {stream_id(), :game_state} =>  %{fod_platforms: %{left: Slp.Events.FodPlatforms.t() | nil, right: Slp.Events.FodPlatforms.t() | nil}}

  ## API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: @global_name)
  end

  @spec initialize_stream() :: Streams.stream_id()
  def initialize_stream do
     GenServer.call(@global_name, :initialize_stream)
  end

  @spec get_event_payloads(Streams.stream_id()) :: {:ok, Slp.Events.EventPayloads.t() | nil} | :error
  def get_event_payloads(stream_id) do
    lookup_helper(stream_id, :event_payloads)
  end

  @spec set_event_payloads(Streams.stream_id(), Slp.Events.EventPayloads.t()) :: :ok
  def set_event_payloads(stream_id, event_payloads) do
    GenServer.call(@global_name, {:set_event_payloads, stream_id, event_payloads})
  end

  @spec set_game_start(Streams.stream_id(), Slp.Events.GameStart.t() | nil) :: :ok
  def set_game_start(stream_id, game_start) do
    GenServer.call(@global_name, {:set_game_start, stream_id, game_start})
  end

  @spec set_fod_platform(Streams.stream_id(), :left | :right, Slp.Events.FodPlatforms.t()) :: :ok
  def set_fod_platform(stream_id, side, event) do
    GenServer.call(@global_name, {:set_fod_platform, stream_id, side, event})
  end

  @spec join_payload(Streams.stream_id()) :: binary()
  def join_payload(stream_id) do
    stream_objects = :ets.select(@current_games_table_name, [{{{stream_id, :_}, :"$1"}, [], [:"$1"]}])

    event_payloads = Enum.find(stream_objects, fn o -> match?(%Slp.Events.EventPayloads{}, o) end)
    game_start = Enum.find(stream_objects, fn o -> match?(%Slp.Events.GameStart{}, o) end)
    game_state = Enum.find(stream_objects, fn o -> match?(%{fod_platforms: _}, o) end)
    state_stages = if is_nil(game_state), do: [], else: Map.values(game_state[:fod_platforms])

    binary_to_send =
      [
        event_payloads,
        game_start
      ] ++ state_stages
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.map(fn e -> e.binary end)
      |> Enum.join()

    binary_to_send
  end

  @spec delete(Streams.stream_id()) :: :ok
  def delete(stream_id) do
    GenServer.call(@global_name, {:delete, stream_id})
  end

  @spec list_streams() :: [%{stream_id: Streams.stream_id(), active_game: Slp.Events.GameStart.t()}]
  def list_streams do
    :ets.select(
      @current_games_table_name,
      [
        {{{:"$1", :game_start}, :"$2"},
        [],
        [%{stream_id: :"$1", active_game: :"$2"}]}
      ]
    )
  end

  ## Callbacks

  @impl true
  def init(_) do
    :ets.new(@current_games_table_name, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call(:initialize_stream, _from, state) do
    # Generate an unused stream ID.
    # Since this happens in a GenServer call, it is the only message being
    # served at the moment, so there is no risk of the same stream_id being
    # handed out again before the first recipient inserts their keys.
    stream_id = generate_stream_id()

    :ets.insert(@current_games_table_name, {{stream_id, :event_payloads}, nil})
    :ets.insert(@current_games_table_name, {{stream_id, :game_start}, nil})
    :ets.insert(@current_games_table_name, {{stream_id, :game_state}, @initial_game_state})

    {:reply, stream_id, state}
  end

  def handle_call({:set_event_payloads, stream_id, event_payloads}, _from, state) do
    # TODO: Protect against inserting for invalid stream?
    :ets.insert(@current_games_table_name, {{stream_id, :event_payloads}, event_payloads})
    {:reply, :ok, state}
  end

  def handle_call({:set_game_start, stream_id, game_start}, _from, state) do
    # TODO: Protect against inserting for invalid stream?
    :ets.insert(@current_games_table_name, {{stream_id, :game_start}, game_start})
    :ets.insert(@current_games_table_name, {{stream_id, :game_state}, @initial_game_state})
    {:reply, :ok, state}
  end

  def handle_call({:set_fod_platform, stream_id, side, event}, _from, state) do
    # TODO: Protect against inserting for invalid stream?
    {:ok, current_game_state} = lookup_helper(stream_id, :game_state)
    :ets.insert(@current_games_table_name, {{stream_id, :game_state}, put_in(current_game_state, [:fod_platforms, side], event)})
    {:reply, :ok, state}
  end

  def handle_call({:delete, stream_id}, _from, state) do
    for event_type <- [:event_payloads, :game_start, :game_state] do
      :ets.delete(@current_games_table_name, {stream_id, event_type})
    end
    {:reply, :ok, state}
  end

  defp lookup_helper(stream_id, event_type) do
    case :ets.lookup(@current_games_table_name, {stream_id, event_type}) do
      [] -> :error
      [{{^stream_id, ^event_type}, object}] -> {:ok, object}
    end
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
end
