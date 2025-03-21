defmodule SpectatorModeWeb.BridgesChannel do
  use SpectatorModeWeb, :channel

  @impl true
  def join("bridges", payload, socket) do
    if authorized?(payload) do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("game_data", payload, socket) do
    IO.inspect(payload, label: "game_data event got payload")
    {:noreply, socket}
  end

  # Add authorization logic here as required.
  defp authorized?(_payload) do
    true
  end
end
