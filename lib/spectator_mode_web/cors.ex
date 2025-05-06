defmodule SpectatorModeWeb.CORS do
  use Corsica.Router, origins: ["https://ssbm.tv"]

  resource "/assets/zips/*", origins: "*", allow_headers: :all
  resource "/*"
end
