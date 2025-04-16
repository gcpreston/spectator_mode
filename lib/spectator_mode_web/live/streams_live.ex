defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-row h-full">
      <div class={"w-full lg:w-96 flex-none h-full flex flex-col px-4 " <> if @selected_bridge_id, do: "hidden lg:block", else: ""}>
        <div class="text-center font-semibold text-xl py-4 max-h-24">Streams</div>
        <div class="justify-center grid grid-cols-1 gap-4 overflow-y-auto">
          <%= if map_size(@relays) == 0 do %>
            <p class="text-center">No current streams.</p>
          <% else %>
            <%= for {bridge_id, active_game} <- @relays do %>
              <button phx-click="watch" phx-value-bridgeid={bridge_id}>
                <.stream_card bridge_id={bridge_id} active_game={active_game} selected={bridge_id == @selected_bridge_id} />
              </button>
            <% end %>
          <% end %>
        </div>
      </div>

      <div class="grow">
        <div class="text-center lg:hidden pt-4 pb-2">
          <button :if={@selected_bridge_id} phx-click="clear">
            <.icon name="hero-arrow-left-start-on-rectangle" class="h-5 w-5" />
            <span>Return to streams</span>
          </button>
        </div>
        <div id="bridge-id-target" bridgeid={@selected_bridge_id}></div>
        <div id="viewer-root" class="w-full" phx-update="ignore"></div>
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
  def handle_event("watch", %{"bridgeid" => bridge_id}, socket) do
    params = %{"watch" => bridge_id}
    {:noreply, push_patch(socket, to: ~p"/?#{params}")}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, clear_watch(socket)}
  end

  @impl true
  def handle_params(%{"watch" => bridge_id}, _uri, socket) do
    socket =
      if Map.has_key?(socket.assigns.relays, bridge_id) do
        assign(socket, :selected_bridge_id, bridge_id)
      else
        socket
        |> clear_watch()
        |> put_flash(:error, "Stream not found.")
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_bridge_id, nil)}
  end

  @impl true
  def handle_info({:relay_created, bridge_id}, socket) do
    {:noreply, update(socket, :relays, fn old_relays -> Map.put(old_relays, bridge_id, nil) end)}
  end

  def handle_info({:relay_destroyed, bridge_id}, socket) do
    socket =
      if bridge_id == socket.assigns.selected_bridge_id do
        socket
        |> clear_watch()
        |> put_flash(:info, "This stream is no longer available.")
      else
        socket
      end

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

  defp clear_watch(socket) do
    push_patch(socket, to: ~p"/")
  end
end
