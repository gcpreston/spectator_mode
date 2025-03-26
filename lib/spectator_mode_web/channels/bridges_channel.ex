defmodule SpectatorModeWeb.BridgesChannel do
  use SpectatorModeWeb, :channel

  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.Streams

  @impl true
  def join("bridges", %{"bridge_id" => bridge_id}, socket) do
    # TODO: monitor and shutdown handling
    {:ok, pid} = Streams.start_relay(bridge_id)
    IO.inspect(bridge_id, label: "Started bridge relay")
    {:ok, %{bridge_id: bridge_id}, socket |> assign(:bridge_relay, pid)}
  end

  @impl true
  def handle_in("metadata", {:binary, payload}, socket) do
    BridgeRelay.set_metadata(socket.assigns.bridge_relay, payload)
    {:noreply, socket}
  end

  def handle_in("game_data", {:binary, payload}, socket) do
    BridgeRelay.forward(socket.assigns.bridge_relay, payload)
    {:noreply, socket}
  end
end
