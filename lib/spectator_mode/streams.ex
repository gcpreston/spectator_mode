defmodule SpectatorMode.Streams do
  @moduledoc """
  The Streams context provides a public API for stream management operations.
  """
  alias SpectatorMode.BridgeMonitorRegistry
  alias SpectatorMode.BridgeMonitorSupervisor
  alias SpectatorMode.BridgeMonitor
  alias SpectatorMode.LivestreamSupervisor
  alias SpectatorMode.Livestream
  alias SpectatorMode.Slp.Events.GameStart
  alias SpectatorMode.ReconnectTokenStore

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @type bridge_id() :: String.t()
  @type stream_id() :: integer()
  @type reconnect_token() :: String.t()
  @type connect_result() :: {:ok, bridge_id(), [stream_id()], reconnect_token()} | {:error, term()}

  @doc """
  Subscribe to PubSub notifications about the state
  of active streams.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, @index_subtopic)
  end

  def index_subtopic do
    @index_subtopic
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
  Start a supervised relay process, and link it to the calling process as the
  bridge connection. On success, returns a tuple including the relay pid, the
  generated bridge ID, the generated stream IDs, and the generated reconnect token.
  """
  @spec start_and_link_relay(integer(), pid()) :: connect_result() | :error
  def start_and_link_relay(stream_count, source_pid \\ self()) do
    bridge_id = Ecto.UUID.generate()
    reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)

    with {:ok, livestream_ids_and_pids} <- start_supervised_livestreams(stream_count),
         {:ok, _relay_pid} <- DynamicSupervisor.start_child(BridgeMonitorSupervisor, {BridgeMonitor, {bridge_id, reconnect_token, source_pid}}) do
       {:ok, bridge_id, Enum.map(livestream_ids_and_pids, fn {stream_id, _pid} -> stream_id end), reconnect_token}
    else
      # TODO: This does not handle if an issue arises with BridgeMonitorSupervisor
      {:error, started_livestreams} ->
        cleanup_livestreams(started_livestreams)
        :error
    end
  end

  # TODO: Store bridge_id instead of pid, look up via registry
  @doc """
  Reconnect a relay to the calling process as the bridge connection. Requires
  the correct reconnect token. On success, returns a tuple including the relay
  pid, the generated bridge ID, and the generated reconnect token.
  """
  @spec reconnect_relay(reconnect_token(), pid()) :: connect_result()
  def reconnect_relay(reconnect_token, source_pid \\ self()) do
    with {:ok, bridge_id} <- ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token),
         {:ok, new_reconnect_token} <- BridgeMonitor.reconnect({:via, Registry, {BridgeMonitorRegistry, bridge_id}}, source_pid) do
      {:ok, bridge_id, new_reconnect_token}
    else
      :error -> {:error, :reconnect_token_not_found}
      nil -> {:error, :relay_pid_not_found}
    end
  end

  @doc """
  Fetch the IDs of all currently active bridge relays, and their metadata.
  """
  @spec list_relays() :: [%{bridge_id: bridge_id(), active_game: GameStart.t(), disconnected: boolean()}]
  def list_relays do
    Registry.select(BridgeMonitorRegistry, [{{:"$1", :_, %{active_game: :"$2", disconnected: :"$3"}}, [], [%{bridge_id: :"$1", active_game: :"$2", disconnected: :"$3"}]}])
  end

  ## Helpers

  defp start_supervised_livestreams(stream_count) do
    start_supervised_livestreams(stream_count, [])
  end

  defp start_supervised_livestreams(stream_count, acc) when stream_count <= 0 do
    {:ok, acc}
  end

  defp start_supervised_livestreams(stream_count, acc) do
    # TODO: Track used IDs so as to not re-use
    stream_id = Enum.random(0..((2**32)-1))

    if {:ok, stream_pid} = DynamicSupervisor.start_child(LivestreamSupervisor, {Livestream, stream_id}) do
      start_supervised_livestreams(stream_count - 1, [{stream_id, stream_pid} | acc])
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
