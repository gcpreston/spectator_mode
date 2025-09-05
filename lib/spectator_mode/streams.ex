defmodule SpectatorMode.Streams do
  @moduledoc """
  The Streams context provides a public API for stream management operations.
  """
  alias SpectatorMode.Slp.Events.GameStart
  alias SpectatorMode.BridgeTracker
  alias SpectatorMode.GameTracker

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @type bridge_id() :: String.t()
  @type stream_id() :: integer()
  @type reconnect_token() :: String.t()
  @type bridge_connect_result() ::
          {:ok, bridge_id(), [stream_id()], reconnect_token()} | {:error, term()}
  @type viewer_connect_result() :: {:ok, binary()} | {:error, term()}

  @doc """
  Subscribe to PubSub notifications about the state
  of active streams.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, @index_subtopic)
  end

  def stream_subtopic(stream_id) do
    "#{@pubsub_topic}:#{stream_id}"
  end

  @doc """
  Register a bridge to the system.

  This will generate both the bridge ID and a stream ID for each stream.
  """
  @spec register_bridge(pos_integer()) :: bridge_connect_result()
  def register_bridge(stream_count) do
    {bridge_id, stream_ids, reconnect_token} = BridgeTracker.register(stream_count)
    {:ok, bridge_id, stream_ids, reconnect_token}
  end

  @doc """
  Reconnect a bridge via a reconnect token.
  """
  @spec reconnect_bridge(reconnect_token()) :: bridge_connect_result()
  def reconnect_bridge(reconnect_token) do
    case BridgeTracker.reconnect(reconnect_token) do
      {:ok, reconnect_token, bridge_id, stream_ids} ->
        {:ok, bridge_id, stream_ids, reconnect_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Register the calling process to receive data from a specified livestream.

  Returns the Slippi events from an ongoing game needed to interpret the game
  state. By default, this is a minimal collection, suitable for in-browser
  viewing, but if the full replay so far is needed, the `return_full_replay`
  parameter can be passed as `true`.
  """
  @spec register_viewer(stream_id(), boolean()) :: viewer_connect_result()
  def register_viewer(stream_id, return_full_replay \\ false) do
    # only the correct instance of GameTracker will know about the stream
    join_result =
      if return_full_replay do
        call_stream_node(stream_id, fn -> GameTracker.full_join_payload(stream_id) end)
      else
        call_stream_node(stream_id, fn -> GameTracker.minimal_join_payload(stream_id) end)
      end

    if match?({:ok, _binary}, join_result) do
      Phoenix.PubSub.subscribe(SpectatorMode.PubSub, stream_subtopic(stream_id))
    end

    join_result
  end

  # Execute a function on the node hosting the given stream, and return the result.
  defp call_stream_node(stream_id, fun) do
    case :mnesia.transaction(fn -> :mnesia.read({SpectatorMode.Mnesia.StreamNodes, stream_id}) end) do
      {:atomic, [{SpectatorMode.Mnesia.StreamNodes, ^stream_id, node_name}]} ->
        {:ok, :erpc.call(node_name, fun)}

      {:atomic, []} ->
        {:error, :stream_not_found}

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Forward binary data to livestream subscribers.

  Data is delivered as a message: `{:game_data, binary()}`.
  """
  @spec forward(stream_id(), binary()) :: nil
  def forward(stream_id, data) do
    # Send binary to pubsub subscribers
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      stream_subtopic(stream_id),
      {:game_data, data}
    )

    # Asynchronously parse and update tracked game info as needed
    GameTracker.handle_packet(stream_id, data)
  end

  @doc """
  Fetch the stream IDs of all currently active streams, and their metadata.
  """
  @spec list_streams() :: [
          %{stream_id: stream_id(), active_game: GameStart.t(), disconnected: boolean()}
        ]
  def list_streams do
    game_tracker_streams = GameTracker.list_streams()
    disconnected_streams = BridgeTracker.disconnected_streams()

    Enum.map(game_tracker_streams, fn %{stream_id: stream_id, active_game: game} ->
      disconnected = MapSet.member?(disconnected_streams, stream_id)
      %{stream_id: stream_id, active_game: game, disconnected: disconnected}
    end)
  end

  @spec notify_subscribers(atom(), term()) :: nil
  def notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      @index_subtopic,
      {event, result}
    )
  end
end
