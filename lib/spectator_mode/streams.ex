defmodule SpectatorMode.Streams do
  @moduledoc """
  The Streams context.

  How this wants to work:

  BridgesChannel PID <--link--> BridgeRelay PID
  BridgeRelay PID <--supervise-- RelaySupervisor

  [x] slippi-web-bridge crash => BridgesChannel PID stop
  [ ] BridgesChannel PID => BridgeRelay PID stop
  [ ] BridgeRelay PID stop (expected) => notify "streams:index" subscribers
      - can be implemented in GenServer.terminate
  [ ] BridgeRelay PID stop (unexpected) => restart, re-populate metadata
      - will not call GenServer.terminate
      - DynamicSupervisor will restart
      -
  """
  alias SpectatorMode.BridgeRegistry
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.Slp.Events.GameStart

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @type bridge_id() :: String.t()

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

  @doc """
  Start a supervised bridge relay, and link the newly created process
  to the given source. The idea of this function is to create a relay
  which exits with the source and recovers from crashes, while a relay
  crash does not take down the source process.
  """
  @spec start_and_link_relay(bridge_id(), pid()) :: DynamicSupervisor.on_start_child()
  def start_and_link_relay(bridge_id, source_pid) do
    DynamicSupervisor.start_child(SpectatorMode.RelaySupervisor, {BridgeRelay, {bridge_id, source_pid}})
  end

  @doc """
  Fetch the IDs of all currently active bridge relays, and their metadata.
  """
  @spec list_relays() :: [%{bridge_id: bridge_id(), active_game: GameStart.t()}]
  def list_relays do
    Registry.select(BridgeRegistry, [{{:"$1", :_, :"$2"}, [], [%{bridge_id: :"$1", active_game: :"$2"}]}])
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
