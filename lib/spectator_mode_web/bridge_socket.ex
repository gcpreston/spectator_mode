defmodule SpectatorModeWeb.BridgeSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.BridgeRegistry

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  @impl true
  def connect(state) do
    bridge_id = Ecto.UUID.generate()
    {:ok, _pid} = Streams.start_and_link_relay(bridge_id, self())
    send(self(), :after_join)
    {:ok, Map.put(state, :bridge_id, bridge_id)}
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    # Forward binary game data via the relay
    BridgeRelay.forward({:via, Registry, {BridgeRegistry, state.bridge_id}}, payload)
    {:ok, state}
  end

  @impl true
  def handle_info(:after_join, state) do
    # notify the bridge of its generated id
    {:push, {:text, state.bridge_id}, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
