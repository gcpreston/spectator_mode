defmodule Mix.Tasks.Vite do
  @moduledoc "Printed when the user requests `mix help vite`"
  @shortdoc "Echoes arguments"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    case args do
      ["build" | _rest] -> build()
      _ -> Mix.shell().error("Unknown command")
    end
  end

  defp build do
    # Mix.shell().cmd("cp -r assets/public priv/static")
    Mix.shell().cmd("cd assets && node_modules/vite/bin/vite.js build")
  end
end
