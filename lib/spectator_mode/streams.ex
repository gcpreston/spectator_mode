defmodule SpectatorMode.Streams do
  @moduledoc """
  The Streams context provides a public API for stream management operations.
  """
  alias SpectatorMode.BridgeMonitorRegistry
  alias SpectatorMode.BridgeMonitorSupervisor
  alias SpectatorMode.BridgeMonitor
  alias SpectatorMode.PacketHandlerRegistry
  alias SpectatorMode.PacketHandlerSupervisor
  alias SpectatorMode.PacketHandler
  alias SpectatorMode.Slp.Events.GameStart
  alias SpectatorMode.ReconnectTokenStore
  alias SpectatorMode.GameTracker

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @type bridge_id() :: String.t()
  @type stream_id() :: integer()
  @type reconnect_token() :: String.t()
  @type bridge_connect_result() :: {:ok, bridge_id(), [stream_id()], reconnect_token()} | {:error, term()}
  @type viewer_connect_result() :: binary()

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
  Register a bridge to the system. This function will start the specified
  number of PacketHandler processes, as well as a process to monitor the bridge's
  connection.

  This will generate both the bridge ID and a stream ID for each stream.
  """
  @spec register_bridge(integer(), pid()) :: bridge_connect_result()
  def register_bridge(stream_count, pid \\ self()) do
    bridge_id = Ecto.UUID.generate()
    reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)
    stream_ids = Enum.map(1..stream_count, fn _ -> GameTracker.initialize_stream() end)

    with {:ok, _start_result} <- start_supervised_packet_handlers(stream_ids),
         {:ok, _relay_pid} <- DynamicSupervisor.start_child(BridgeMonitorSupervisor, {BridgeMonitor, {bridge_id, stream_ids, reconnect_token, pid}}) do

      {:ok, bridge_id, stream_ids, reconnect_token}
    else
      # TODO: This does not handle if an issue arises with BridgeMonitorSupervisor
      {:error, started_packet_handlers} ->
        cleanup_packet_handlers(started_packet_handlers)
        {:error, :livestream_start_failure}
    end
  end

  @doc """
  Reconnect a bridge via a reconnect token.
  """
  @spec reconnect_bridge(reconnect_token(), pid()) :: bridge_connect_result()
  def reconnect_bridge(reconnect_token, pid \\ self()) do
    with {:ok, bridge_id} <- ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token),
         :ok <- ReconnectTokenStore.delete({:global, ReconnectTokenStore}, reconnect_token),
         {:ok, new_reconnect_token, stream_ids} <- BridgeMonitor.reconnect({:via, Registry, {BridgeMonitorRegistry, bridge_id}}, pid) do
      {:ok, bridge_id, stream_ids, new_reconnect_token}
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
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, stream_subtopic(stream_id))
    GameTracker.join_payload(stream_id)
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
    PacketHandler.handle_packet({:via, Registry, {PacketHandlerRegistry, stream_id}}, data)
  end

  @doc """
  Fetch the stream IDs of all currently active streams, and their metadata.
  """
  @spec list_streams() :: [%{stream_id: stream_id(), active_game: GameStart.t()}]
  def list_streams do
    GameTracker.list_streams()
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

  defp start_supervised_packet_handlers(stream_count) do
    start_supervised_packet_handlers(stream_count, [])
  end

  defp start_supervised_packet_handlers([], acc) do
    {:ok, acc}
  end

  defp start_supervised_packet_handlers([stream_id | rest], acc) do
    if {:ok, stream_pid} = DynamicSupervisor.start_child(PacketHandlerSupervisor, {PacketHandler, stream_id}) do
      # TODO: This feels like a recipe for bad frontend state,
      # would rather an all-at-once notification on success
      notify_subscribers(:livestream_created, stream_id)
      start_supervised_packet_handlers(rest, [{stream_id, stream_pid} | acc])
    else
      {:error, acc}
    end
  end

  defp cleanup_packet_handlers(started_packet_handlers) do
    for {_stream_id, stream_pid} <- started_packet_handlers do
      DynamicSupervisor.terminate_child(PacketHandlerSupervisor, stream_pid)
    end
  end
end
