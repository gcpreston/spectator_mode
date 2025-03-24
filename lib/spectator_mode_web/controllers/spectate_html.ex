defmodule SpectatorModeWeb.SpectateHTML do
  @moduledoc """
  This module contains pages rendered by SpectateController.

  See the `spectate_html` directory for all templates available.
  """
  use SpectatorModeWeb, :html

  embed_templates "spectate_html/*"
end
