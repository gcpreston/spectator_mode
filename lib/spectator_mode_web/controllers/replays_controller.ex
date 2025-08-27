defmodule SpectatorModeWeb.ReplaysController do
  use SpectatorModeWeb, :controller

  alias SpectatorMode.Streams

  def index(conn, _params) do
    streams = Streams.list_streams()
    render(conn, :index, replays: streams)
  end

  def show(conn, %{"filename" => filename}) do
    bytes_start_str = Plug.Conn.get_req_header(conn, "bytes")
    bytes_start = if bytes_start_str, do: String.to_integer(bytes_start_str), else: 0
    [stream_id_str] = Regex.run(~r/^(.+)\.slp/, filename, capture: :all_but_first)
    stream_id = String.to_integer(stream_id_str)
    send_download(conn, {:binary, Streams.get_replay(stream_id, bytes_start)}, filename: filename)
  end
end
