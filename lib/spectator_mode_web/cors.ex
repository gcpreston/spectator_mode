defmodule SpectatorModeWeb.CORS do
  use Corsica.Router, origins: ["https://spectatormode.tv"]

  resource "/assets/zips/*", origins: "*", allow_headers: :all
  resource "/*"
end
