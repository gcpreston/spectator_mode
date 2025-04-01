defmodule SpectatorModeWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :spectator_mode

  socket "/socket", SpectatorModeWeb.UserSocket,
    websocket: true,
    longpoll: false

  socket "/bridge_socket", SpectatorModeWeb.BridgeSocket,
    websocket: [timeout: 180_000],
    longpoll: false

  socket "/viewer_socket", SpectatorModeWeb.ViewerSocket,
    websocket: [timeout: 180_000],
    longpoll: false

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_spectator_mode_key",
    signing_salt: "zgJVpr7N",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :spectator_mode,
    gzip: false,
    only: SpectatorModeWeb.static_paths()

  if Mix.env() == :dev do
    plug Plug.Static,
      at: "/assets",
      from: "assets/public",
      gzip: false
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :spectator_mode
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SpectatorModeWeb.Router
end
