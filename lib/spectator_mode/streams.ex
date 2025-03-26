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

  @pubsub_topic "streams"
  @index_subtopic "#{@pubsub_topic}:index"

  @doc """
  Subscribe to PubSub notifications about the state
  of active streams.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(SpectatorMode.PubSub, @index_subtopic)
  end

  # I feel it's better to have start_relay here than implemented as
  # a call in StreamsManager for simplicity. One downside is extraneous
  # created/destroyed messages on crash and restart.
  # A solution would be some kind of debounce mechanism for the UI;
  # it shouldn't be necessary for subscribers in code, and it more
  # accurate than the other solution in that regard.

  @doc """
  Start a supervised bridge relay.
  """
  def start_relay(bridge_id) do
    DynamicSupervisor.start_child(SpectatorMode.RelaySupervisor, {BridgeRelay, bridge_id})
  end

  @doc """
  Stop a supervised bridge relay.
  """
  def stop_relay(bridge_id) do
    GenServer.stop({:via, Registry, {BridgeRegistry, bridge_id}})
    notify_subscribers(:relay_destroyed, bridge_id)
  end

  def list_relays do
    Registry.select(BridgeRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  defp notify_subscribers(event, result) do
    Phoenix.PubSub.broadcast(
      SpectatorMode.PubSub,
      @index_subtopic,
      {event, result}
    )
  end
end
