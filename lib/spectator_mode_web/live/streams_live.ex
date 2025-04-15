defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p class="text-center italic text-xl">Streams:</p>
      <div class="justify-center grid grid-cols-1 gap-4 mt-6">
        <%= for %{bridge_id: bridge_id, metadata: _metadata} <- @relays do %>
          <a href={~p"/watch/#{bridge_id}"}>
            <.stream_card bridge_id={bridge_id} />
          </a>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
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
