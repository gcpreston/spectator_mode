defmodule SpectatorMode.Streams do
  @moduledoc """
  The Streams context provides a public API for stream management operations.
  """
  alias SpectatorMode.BridgeRegistry
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.Slp.Events.GameStart
  alias SpectatorMode.ReconnectTokenStore

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @type bridge_id() :: String.t()
  @type reconnect_token() :: String.t()
  @type connect_result() :: {:ok, pid(), bridge_id(), reconnect_token()} | {:error, term()}

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
  generated bridge ID, and the generated reconnect token.
  """
  @spec start_and_link_relay(pid()) :: connect_result()
  def start_and_link_relay(source_pid \\ self()) do
    bridge_id = Ecto.UUID.generate()
    reconnect_token = ReconnectTokenStore.register({:global, ReconnectTokenStore}, bridge_id)
    {:ok, relay_pid} = DynamicSupervisor.start_child(SpectatorMode.RelaySupervisor, {BridgeRelay, {bridge_id, reconnect_token, source_pid}})

    {:ok, relay_pid, bridge_id, reconnect_token}
  end

  @doc """
  Reconnect a relay to the calling process as the bridge connection. Requires
  the correct reconnect token. On success, returns a tuple including the relay
  pid, the generated bridge ID, and the generated reconnect token.
  """
  @spec reconnect_relay(reconnect_token(), pid()) :: connect_result()
  def reconnect_relay(reconnect_token, source_pid \\ self()) do
    with {:ok, bridge_id} <- ReconnectTokenStore.fetch({:global, ReconnectTokenStore}, reconnect_token),
         relay_pid when is_pid(relay_pid) <- lookup(bridge_id),
         {:ok, new_reconnect_token} <- BridgeRelay.reconnect(relay_pid, source_pid) do
      {:ok, relay_pid, bridge_id, new_reconnect_token}
    end
  end

  @doc """
  Fetch the IDs of all currently active bridge relays, and their metadata.
  """
  @spec list_relays() :: [%{bridge_id: bridge_id(), active_game: GameStart.t(), disconnected: boolean()}]
  def list_relays do
    Registry.select(BridgeRegistry, [{{:"$1", :_, %{active_game: :"$2", disconnected: :"$3"}}, [], [%{bridge_id: :"$1", active_game: :"$2", disconnected: :"$3"}]}])
  end

  @doc """
  Find PID of the relay process for a given bridge ID. If no such relay
  process exists, returns `nil`.
  """
  @spec lookup(bridge_id()) :: pid() | nil
  def lookup(bridge_id) do
    case Registry.lookup(BridgeRegistry, bridge_id) do
      [{pid, _value} | _rest] -> pid # _rest should always be [] due to unique keys
      _ -> nil
    end
  end
end
