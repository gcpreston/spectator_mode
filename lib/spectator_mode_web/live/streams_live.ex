defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-row h-full">
      <div class="border w-96 flex-none h-full flex flex-col">
        <div class="text-center font-semibold text-xl py-4 max-h-24">Streams</div>
        <div class="justify-center grid grid-cols-1 gap-4 overflow-y-auto">
          <%= if Map.size(@relays) == 0 do %>
            <p class="text-center">No current streams.</p>
          <% else %>
            <%= for {bridge_id, active_game} <- @relays do %>
              <a href={~p"/watch/#{bridge_id}"}>
                <.stream_card bridge_id={bridge_id} active_game={active_game} />
              </a>
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="border grow">
        Main area
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
