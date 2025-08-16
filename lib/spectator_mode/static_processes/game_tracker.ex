# What functionality is needed?
# - streams_live looks up all game states in one fell swoop
# - streams_live receives a :game_update event from Streams to give new game states
# - Livestream MUST to be able to recover it from somewhere. The existing functionaltiy
#   can't be broken, but can have implementations changed if it makes sense.

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
  @event_types [:event_payloads, :game_start, :game_state]

  # ETS schema
  # {stream_id(), :event_payloads} => Slp.Events.EventPayloads.t()
  # {stream_id(), :game_start} => Slp.Events.GameStart.t()
  # {stream_id(), :game_state} =>  %{fod_platforms: %{left: Slp.Events.FodPlatform.t(), right: Slp.Events.FodPlatform.t()}}

  ## API

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: @global_name)
  end

  @spec initialize_stream(Streams.stream_id()) :: :ok
  def initialize_stream(stream_id) do
     GenServer.call(@global_name, {:initialize_stream, stream_id})
  end

  @spec get_event_payloads(Streams.stream_id()) :: {:ok, Slp.Events.EventPayloads.t() | nil} | :error
  def get_event_payloads(stream_id) do
    lookup_helper(stream_id, :event_payloads)
  end

  @spec set_event_payloads(Streams.stream_id(), Slp.Events.EventPayloads.t()) :: :ok
  def set_event_payloads(stream_id, event_payloads) do
    GenServer.call(@global_name, {:set_event_payloads, stream_id, event_payloads})
  end

  @spec get_game_start(Streams.stream_id()) :: {:ok, Slp.Events.GameStart.t() | nil} | :error
  def get_game_start(stream_id) do
    lookup_helper(stream_id, :game_start)
  end

  @spec set_game_start(Streams.stream_id(), Slp.Events.GameStart.t() | nil) :: :ok
  def set_game_start(stream_id, game_start) do
    GenServer.call(@global_name, {:set_game_start, stream_id, game_start})
  end

  # TODO: Game state setters

  @spec join_payload(Streams.stream_id()) :: {:ok, binary()} | :error
  def join_payload(stream_id) do
    stream_objects = :ets.select(@current_games_table_name, [{{{stream_id, :_}, :"$1"}, [], [:"$1"]}]) |> dbg()

    event_payloads = Enum.find(stream_objects, fn o -> match?(%Slp.Events.EventPayloads{}, o) end)
    game_start = Enum.find(stream_objects, fn o -> match?(%Slp.Events.GameStart{}, o) end)
    stage_states = Enum.filter(stream_objects, fn o -> match?(%Slp.Events.FodPlatforms{}, o) end)

    binary_to_send =
      [
        event_payloads,
        game_start
      ] ++ stage_states
      |> Enum.filter(&(!is_nil(&1)))
      |> Enum.map(fn e -> e.binary end)
      |> Enum.join()

    {:ok, binary_to_send}
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
    |> dbg()
  end

  ## Callbacks

  @impl true
  def init(_) do
    :ets.new(@current_games_table_name, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, nil}
  end

  @impl true
  def handle_call({:initialize_stream, stream_id}, _from, state) do
    for event_type <- @event_types do
      :ets.insert(@current_games_table_name, {{stream_id, event_type}, nil})
    end
    {:reply, :ok, state}
  end

  def handle_call({:set_event_payloads, stream_id, event_payloads}, _from, state) do
    # TODO: Protect against inserting for invalid stream?
    :ets.insert(@current_games_table_name, {{stream_id, :event_payloads}, event_payloads})
    {:reply, :ok, state}
  end

  def handle_call({:set_game_start, stream_id, game_start}, _from, state) do
    # TODO: Protect against inserting for invalid stream?
    :ets.insert(@current_games_table_name, {{stream_id, :game_start}, game_start})
    {:reply, :ok, state}
  end

  def handle_call({:delete, stream_id}, _from, state) do
    for event_type <- @event_types do
      :ets.delete(@current_games_table_name, {stream_id, event_type})
    end
    {:reply, :ok, state}
  end

  defp lookup_helper(stream_id, event_type) do
    case :ets.lookup(@current_games_table_name, {stream_id, event_type}) do
      [] -> :error
      [event] -> {:ok, event}
    end
  end
end
