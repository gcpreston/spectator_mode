defmodule SpectatorModeWeb.BridgesChannel do
  use SpectatorModeWeb, :channel

  alias SpectatorMode.BridgeRelay
  alias SpectatorMode.StreamsManager
  alias SpectatorMode.Streams

  @impl true
  def join("bridges", %{"bridge_id" => bridge_id}, socket) do
    {:ok, pid} = Streams.start_relay(bridge_id)
    IO.inspect(bridge_id, label: "Started bridge relay")
    # TODO: Should this and start_relay be rolled into one function
    #   meant to be called from the eventual source?
    StreamsManager.start_source_monitor(bridge_id)

    {:ok, %{bridge_id: bridge_id}, socket |> assign(:bridge_relay, pid)}
  end

  @impl true
  def handle_in("metadata", {:binary, payload}, socket) do
    BridgeRelay.set_metadata(socket.assigns.bridge_relay, payload)
    {:noreply, socket}
  end

  def handle_in("game_data", {:binary, payload}, socket) do
    # TODO: Since the source is well-defined, what should this API look like?
    BridgeRelay.forward(socket.assigns.bridge_relay, payload)
    {:noreply, socket}
  end
end
