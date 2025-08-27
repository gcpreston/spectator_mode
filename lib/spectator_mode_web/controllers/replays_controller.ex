defmodule SpectatorModeWeb.ReplaysController do
  use SpectatorModeWeb, :controller

  alias SpectatorMode.Streams

  def index(conn, _params) do
    streams = Streams.list_streams()
    render(conn, :index, replays: streams)
  end
end
