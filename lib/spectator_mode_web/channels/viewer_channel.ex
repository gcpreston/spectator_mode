defmodule SpectatorModeWeb.ViewerChannel do
  use SpectatorModeWeb, :channel

  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.BridgeRegistry

  @impl true
  def join("view:none", _payload, socket) do
    IO.puts("Joined view:none")
    {:ok, socket}
  end

  def join("view:" <> bridge_id, _payload, socket) do
    bridge_relay_name = {:via, Registry, {BridgeRegistry, bridge_id}}
    BridgeRelay.subscribe(bridge_relay_name)
    {:ok, socket}
  end

  @impl true
  def handle_info({:game_data, payload}, socket) do
    push(socket, "game_data", {:binary, payload})
    {:noreply, socket}
  end
end
