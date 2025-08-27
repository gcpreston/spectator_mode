defmodule SpectatorModeWeb.ReplaysController do
  use SpectatorModeWeb, :controller

  alias SpectatorMode.Streams

  def index(conn, _params) do
    streams = Streams.list_streams()
    render(conn, :index, replays: streams)
  end

  def show(conn, %{"filename" => filename}) do
    [stream_id_str] = Regex.run(~r/^(.+)\.slp/, filename, capture: :all_but_first)
    stream_id = String.to_integer(stream_id_str)
    send_download(conn, {:binary, Streams.get_replay(stream_id)}, filename: filename)
  end
end
