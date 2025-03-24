defmodule SpectatorModeWeb.SpectateController do
  use SpectatorModeWeb, :controller

  def show(conn, %{"bridge_id" => bridge_id}) do
    render(conn, :show, layout: false, bridge_id: bridge_id)
  end
end
