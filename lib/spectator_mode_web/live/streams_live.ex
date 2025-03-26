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

    {:ok, socket |> assign(:relays, MapSet.new(Streams.list_relays()))}
  end

  @impl true
  def handle_info({:relay_created, bridge_id}, socket) do
    {:noreply, update(socket, :relays, fn old_relays -> MapSet.put(old_relays, bridge_id) end)}
  end

  def handle_info({:relay_destroyed, bridge_id}, socket) do
    {
      :noreply,
      update(socket, :relays, fn old_relays ->
        MapSet.delete(old_relays, bridge_id)
      end)
    }
  end
end
