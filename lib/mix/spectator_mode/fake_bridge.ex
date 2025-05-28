defmodule Mix.SpectatorMode.FakeBridge do
  use WebSockex

  def start_link(state) do
    WebSockex.start_link("ws://localhost:4000/bridge_socket/websocket", __MODULE__, state)
  end
end
