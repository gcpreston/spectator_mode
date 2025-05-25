defmodule SpectatorModeWeb.ViewerSocket do
  @behaviour Phoenix.Socket.Transport

  require Logger
  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.BridgeRegistry
  alias SpectatorModeWeb.Presence

  @impl true
  def child_spec(_opts) do
    :ignore
  end

  @impl true
  def connect(%{params: %{"bridge_id" => bridge_id}} = state) do
    bridge_relay_name = {:via, Registry, {BridgeRegistry, bridge_id}}
    maybe_current_game = BridgeRelay.subscribe(bridge_relay_name)

    if maybe_current_game do
      send(self(), {:after_join, maybe_current_game})
    end

    # Track presence
    viewer_id = Ecto.UUID.generate()
    Presence.track_viewer(viewer_id, bridge_id)

    {:ok, state}
  end

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_in({payload, [opcode: :binary]}, state) do
    BridgeRelay.forward(state.bridge_relay, payload)
    {:reply, :ok, {:binary, payload}, state}
  end

  @impl true
  def handle_info({:after_join, current_game}, state) do
    # Forward the current game binary to the specator who just connected
    {:push, {:binary, current_game}, state}
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
