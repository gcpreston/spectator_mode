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
    join_payload = BridgeRelay.subscribe(bridge_relay_name)

    # Send initial data to viewer after connect
    if join_payload do
      send(self(), {:after_join, join_payload})
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
  def handle_info({:after_join, join_payload}, state) do
    {:push, {:binary, join_payload}, state}
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
