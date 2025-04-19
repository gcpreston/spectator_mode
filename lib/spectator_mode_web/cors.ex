defmodule SpectatorModeWeb.CORS do
  use Corsica.Router, origins: []

  resource "/*"
  resource "/assets/zips/*", origins: "*", allow_headers: :all
end
