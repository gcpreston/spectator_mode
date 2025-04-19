defmodule SpectatorModeWeb.CORS do
  use Corsica.Router, origins: []

  resource "/*"
  resource "/assets/zips/*", origins: "*"
end
