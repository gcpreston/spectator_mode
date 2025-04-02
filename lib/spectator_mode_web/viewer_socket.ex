defmodule SpectatorModeWeb.ViewerSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.BridgeRegistry

  @impl true
  def child_spec(_opts) do
    # We won't spawn any process, so let's ignore the child spec
    :ignore
  end

  @impl true
  def connect(%{params: %{"bridge_id" => bridge_id}} = state) do
    bridge_relay_name = {:via, Registry, {BridgeRegistry, bridge_id}}
    maybe_current_metadata = BridgeRelay.subscribe(bridge_relay_name)

    if maybe_current_metadata do
      send(self(), {:after_join, maybe_current_metadata})
    end

    {:ok, state}
  end

  @impl true
  def init(state) do
    # Now we are effectively inside the process that maintains the socket.
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    # TODO: Handle metadata
    BridgeRelay.forward(state.bridge_relay, payload)
    {:reply, :ok, {:binary, payload}, state}
  end

  @impl true
  def handle_info({:after_join, current_metadata}, state) do
    # forward the current game metadata to the specator who just connected
    {:push, {:binary, current_metadata}, state}
  end

  def handle_info({:game_data, payload}, state) do
    {:push, {:binary, payload}, state}
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
