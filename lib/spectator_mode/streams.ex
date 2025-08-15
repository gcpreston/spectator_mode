defmodule SpectatorMode.Streams do
  @moduledoc """
  The Streams context provides a public API for stream management operations.
  """
  alias SpectatorMode.BridgeMonitorRegistry
  alias SpectatorMode.BridgeMonitorSupervisor
  alias SpectatorMode.BridgeMonitor
  alias SpectatorMode.LivestreamRegistry
  alias SpectatorMode.LivestreamSupervisor
  alias SpectatorMode.Livestream
  alias SpectatorMode.Slp.Events.GameStart
  alias SpectatorMode.ReconnectTokenStore
  alias SpectatorMode.StreamIDManager
  alias SpectatorMode.GameTracker

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @type bridge_id() :: String.t()
  @type stream_id() :: integer()
  @type reconnect_token() :: String.t()
  @type bridge_connect_result() :: {:ok, bridge_id(), [stream_id()], reconnect_token()} | {:error, term()}
  @type viewer_connect_result() :: {:ok, binary()}

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

  # CHANGES DESIRED
  # - Differentiate between bridge_disconnected and bridge_stopped events
  #   * Show reconnecting message instead of exiting stream on disconnect; exit on stop
  # - Can keep registry as source of truth for listing streams
  #   * relay_created event on reconnect can show it to people on the page,
  #     meanwhile bridge_disconnected can not remove it from those who already saw
  # - Show some kind of indicator that a listed stream is disconnected
  # - Handle trying to watch a disconnected stream
  #   * Say a stream goes down only for a second and people join at this second. Still
  #     want it to be smooth for them.
  #   * What is relay didn't go down as soon as socket did? The socket can go in and out,
  #     and once we determine it's not coming back (reconnect token deletion), we delete the
  #     relay. This could even simplify reconnect token store logic.
  # - Make sure reconnect attempt goes through on server-side crash (may be a client-side issue)

  @doc """
  Register a bridge to the system. This function will start the specified
  number of Livestream processes, as well as a process to monitor the bridge's
  connection.

  This will generate both the bridge ID and a stream ID for each stream.
  """
  @spec register_bridge(integer(), pid()) :: bridge_connect_result()
  def register_bridge(stream_count, pid \\ self()) do
    bridge_id = Ecto.UUID.generate()
    reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)

    with {:ok, stream_ids} <- start_supervised_livestreams(stream_count),
         {:ok, _relay_pid} <- DynamicSupervisor.start_child(BridgeMonitorSupervisor, {BridgeMonitor, {bridge_id, stream_ids, reconnect_token, pid}}) do
       {:ok, bridge_id, stream_ids, reconnect_token}
    else
      # TODO: This does not handle if an issue arises with BridgeMonitorSupervisor
      {:error, started_livestreams} ->
        cleanup_livestreams(started_livestreams)
        {:error, :livestream_start_failure}
    end
  end

  @doc """
  Reconnect a bridge via a reconnect token.
  """
  @spec reconnect_bridge(reconnect_token(), pid()) :: bridge_connect_result()
  def reconnect_bridge(reconnect_token, pid \\ self()) do
    with {:ok, bridge_id} <- ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token),
         {:ok, new_reconnect_token} <- BridgeMonitor.reconnect({:via, Registry, {BridgeMonitorRegistry, bridge_id}}, pid) do
      # TODO: Either look up which stream IDs belong to this bridge and send those back,
      #   or send only a new reconnect token since that's all swb needs
      #   (make sure swb can parse this though, will need to tell the difference between connect and reconnect)
      {:ok, bridge_id, [], new_reconnect_token}
    else
      # TODO: Test case of monitor having died. Should not run into this case
      #   but might need a try-catch to handle it anyways.
      :error -> {:error, :reconnect_token_not_found}
    end
  end

  @doc """
  Register the calling process to receive data from a specified livestream.
  """
  @spec register_viewer(stream_id()) :: viewer_connect_result()
  def register_viewer(stream_id) do
    # Livestream.subscribe({:via, Registry, {LivestreamRegistry, stream_id}})

    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, stream_subtopic(stream_id))
    GameTracker.join_payload(stream_id)
  end

  @doc """
  Forward binary data to a specified livestream.
  """
  @spec forward(stream_id(), binary()) :: nil
  def forward(stream_id, data) do
    Livestream.forward({:via, Registry, {LivestreamRegistry, stream_id}}, data)
  end

  @doc """
  Fetch the stream IDs of all currently active streams, and their metadata.
  """
  @spec list_streams() :: [%{stream_id: stream_id(), active_game: GameStart.t()}]
  def list_streams do
    # Registry.select(
    #   LivestreamRegistry,
    #   [
    #     {{:"$1", :_, %{active_game: :"$2"}},
    #     [],
    #     [%{stream_id: :"$1", active_game: :"$2"}]}
    #   ]
    # )
    GameTracker.list_streams()
  end

  @doc """
  Fetch the bridge IDs of all currently active streams, and their metadata.
  """
  @spec list_bridges() :: [%{bridge_id: bridge_id(), disconnected: GameStart.t()}]
  def list_bridges do
    Registry.select(
      BridgeMonitorRegistry,
      [
        {{:"$1", :_, %{active_game: :"$2"}},
        [],
        [%{stream_id: :"$1", active_game: :"$2"}]}
      ]
    )
  end

  @spec notify_subscribers(atom(), term()) :: nil
  def notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      @index_subtopic,
      {event, result}
    )
  end

  ## Helpers

  defp start_supervised_livestreams(stream_count) do
    start_supervised_livestreams(stream_count, [])
  end

  defp start_supervised_livestreams(stream_count, acc) when stream_count <= 0 do
    {:ok, acc}
  end

  defp start_supervised_livestreams(stream_count, acc) do
    stream_id = StreamIDManager.generate_stream_id()

    if {:ok, _stream_pid} = DynamicSupervisor.start_child(LivestreamSupervisor, {Livestream, stream_id}) do
      start_supervised_livestreams(stream_count - 1, [stream_id | acc])
    else
      {:error, acc}
    end
  end

  defp cleanup_livestreams(started_livestreams) do
    for {_stream_id, stream_pid} <- started_livestreams do
      DynamicSupervisor.terminate_child(LivestreamSupervisor, stream_pid)
    end
  end
end
