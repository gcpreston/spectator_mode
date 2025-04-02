defmodule SpectatorModeWeb.SpectateController do
  use SpectatorModeWeb, :controller

  alias SpectatorMode.Streams

  def show(conn, %{"bridge_id" => bridge_id}) do
    if Streams.lookup(bridge_id) do
      render(conn, :show, layout: false, bridge_id: bridge_id)
    else
      conn
      |> put_flash(:error, "Stream not found.")
      |> redirect(to: ~p"/")
    end
  end
end
