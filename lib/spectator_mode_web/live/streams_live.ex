defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p class="text-center italic text-xl">Streams:</p>
      <div class="justify-center grid grid-cols-1 gap-4 mt-6">
        <%= for {bridge_id, active_game} <- @relays do %>
          <a href={~p"/watch/#{bridge_id}"}>
            <.stream_card bridge_id={bridge_id} active_game={active_game} />
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

    relays_bridge_id_to_active_game_map =
      for %{bridge_id: bridge_id, active_game: game_start} <- Streams.list_relays(), into: %{} do
        {bridge_id, game_start}
      end

    {
      :ok,
      socket
      |> assign(:relays, relays_bridge_id_to_active_game_map)
    }
  end

  @impl true
  def handle_info({:relay_created, bridge_id}, socket) do
    {:noreply, update(socket, :relays, fn old_relays -> Map.put(old_relays, bridge_id, nil) end)}
  end

  def handle_info({:relay_destroyed, bridge_id}, socket) do
    {
      :noreply,
      update(socket, :relays, fn old_relays ->
        Map.delete(old_relays, bridge_id)
      end)
    }
  end

  def handle_info({:game_update, {bridge_id, maybe_event}}, socket) do
    {:noreply, update(socket, :relays, fn old_relays -> Map.put(old_relays, bridge_id, maybe_event) end)}
  end
end
