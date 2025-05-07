defmodule SpectatorModeWeb.CORS do
  use Corsica.Router, origins: ["https://ssbm.tv", "https://spectator-mode.fly.dev"]

  resource "/assets/zips/*", origins: "*", allow_headers: :all
  resource "/*"
end
