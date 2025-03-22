defmodule SpectatorModeWeb.BridgesChannel do
  use SpectatorModeWeb, :channel

  alias SpectatorMode.BridgeRelay

  @impl true
  def join("bridges", _payload, socket) do
    uuid = Ecto.UUID.generate()
    # TODO: monitor and shutdown handling
    {:ok, pid} = BridgeRelay.start_link(uuid)
    IO.inspect(uuid, label: "Started bridge relay")
    {:ok, %{bridge_id: uuid}, socket |> assign(:bridge_relay, pid)}
  end

  @impl true
  def handle_in("game_data", payload, socket) do
    BridgeRelay.forward(socket.assigns.bridge_relay, payload)
    {:noreply, socket}
  end
end
