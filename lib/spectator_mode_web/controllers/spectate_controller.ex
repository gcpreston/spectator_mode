defmodule SpectatorModeWeb.SpectateController do
  use SpectatorModeWeb, :controller

  def show(conn, _params) do
    render(conn, :show, layout: false)
  end
end
 