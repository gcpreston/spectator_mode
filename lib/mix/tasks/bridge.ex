defmodule Mix.Tasks.Bridge do
  @moduledoc """
  Run a dummy bridge, for testing without opening Slippi and the client.
  """
  @shortdoc "Run a test bridge"

  use Mix.Task
  alias Mix.SpectatorMode.FakeBridge

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Starting fake bridge...")
    FakeBridge.start_link([])
  end
end
