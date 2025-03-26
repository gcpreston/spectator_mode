defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p>Streams:</p>
      <ul>
        <li :for={bridge_id <- @relays}>
          <a href={~p"/watch/#{bridge_id}"}>{bridge_id}</a>
        </li>
      </ul>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      IO.puts("Subscribing to streams")
      Streams.subscribe()
    end

    {:ok, socket |> assign(:relays, Streams.list_relays())}
  end

  @impl true
  def handle_info({:relay_created, bridge_id}, socket) do
    {:noreply, update(socket, :relays, fn old_relays -> [bridge_id | old_relays] end)}
  end

  def handle_info({:relay_destroyed, bridge_id}, socket) do
    {
      :noreply,
      update(socket, :relays, fn old_relays ->
        Enum.filter(old_relays, fn b -> b != bridge_id end)
      end)
    }
  end
end
