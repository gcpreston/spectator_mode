defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.BridgeUtils

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p>Streams:</p>
      <ul>
        <li :for={bridge_id <- @bridges}>
          <a href={~p"/watch/#{bridge_id}"}>{bridge_id}</a>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:bridges, BridgeUtils.list_bridges())}
  end
end
