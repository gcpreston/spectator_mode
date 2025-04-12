defmodule SpectatorModeWeb.BridgeSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.Streams
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.BridgeRegistry

  @impl true
  def child_spec(_opts) do
    # We won't spawn any process, so let's ignore the child spec
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
    # Now we are effectively inside the process that maintains the socket.
    # dbg(state)
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    BridgeRelay.forward({:via, Registry, {BridgeRegistry, state.bridge_id}}, payload)
    {:ok, state}
  end

  # TODO: Handle metadata

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
