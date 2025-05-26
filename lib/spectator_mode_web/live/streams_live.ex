defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams
  alias SpectatorModeWeb.Presence

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-row h-full">
      <div class={"w-full lg:w-96 flex-none h-full flex flex-col border-r border-gray-400 " <> if @selected_bridge_id, do: "hidden lg:flex", else: ""}>
        <.link patch="/" class="text-center font-semibold text-xl italic py-2 border-b border-gray-400">
          SpectatorMode
        </.link>

        <div class="grow justify-start flex flex-col gap-4 overflow-y-auto bg-gray-100 p-4">
          <%= if map_size(@relays) == 0 do %>
            <p class="text-center">No current streams.</p>
          <% else %>
            <%= for {bridge_id, %{active_game: active_game, disconnected: disconnected, viewer_count: viewer_count}} <- @relays do %>
              <button phx-click="watch" phx-value-bridgeid={bridge_id}>
                <.stream_card
                  bridge_id={bridge_id}
                  active_game={active_game}
                  selected={bridge_id == @selected_bridge_id}
                  disconnected={disconnected}
                  viewer_count={viewer_count}
                />
              </button>
            <% end %>
          <% end %>
        </div>

        <.bottom_bar />
      </div>

      <div class="grow overflow-y-auto">
        <div class="text-center pt-4 pb-2">
          <button :if={@selected_bridge_id} phx-click="clear">
            <.icon name="hero-arrow-left-start-on-rectangle" class="h-5 w-5" />
            <span>Close stream</span>
          </button>
        </div>
        <div id="bridge-id-target" bridgeid={@selected_bridge_id} phx-hook="BridgeIdHook"></div>
        <slippi-viewer id="viewer" zips-base-url="/assets" phx-update="ignore"></slippi-viewer>
        <div :if={!@selected_bridge_id} class="text-center italic">
          Click on a stream to get started
        </div>
      </div>
    </div>
    """
  end

  def bottom_bar(assigns) do
    ~H"""
    <div class="border-t border-gray-400">
      <div class="flex flex-row justify-between">
        <div class="flex flex-row gap-2 p-2">
          <.link href="https://github.com/gcpreston/spectator_mode" target="_blank">
            <.icon name="github" class="w-8 h-8 text-gray-800" />
          </.link>

          <.link href="https://github.com/gcpreston/spectator_mode/issues/new" target="_blank">
            <.icon name="hero-bug-ant" class="w-8 h-8 text-gray-800" />
          </.link>
        </div>

        <button class="font-medium p-2" phx-click={show_modal("help-modal")}>
          <.icon name="hero-question-mark-circle" class="w-8 h-8 text-gray-800" /> Help
        </button>
      </div>

      <.modal id="help-modal">
        <.header>Instructions</.header>
        <.list>
          <:item title="How to spectate">
            <ul class="text-left list-disc">
              <li>Click or tap on a stream in the list</li>
              <li>To stop watching, click or tap on "Close stream"</li>
            </ul>
          </:item>
          <:item title="How to stream">
            <div class="text-left">
              <ul class="list-disc">
                <li>
                  <.link href="https://github.com/gcpreston/swb-rs/releases/latest" target="_blank" class="underline">
                    Download the latest version of the swb client
                  </.link>
                </li>
                <li>Start Slippi Dolphin</li>
                <li>Extract the downloaded folder and run the swb program inside (double click, or launch from terminal)</li>
                <li>The stream ID will be given upon successful connection</li>
              </ul>
              <p class="mt-4">
                More information and troubleshooting instructions can be found on the <.link
                  href="https://github.com/gcpreston/swb-rs/blob/main/README.md"
                  target="_blank"
                  class="underline"
                >repository's README</.link>.
              </p>
            </div>
          </:item>
        </.list>
      </.modal>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Streams.subscribe()
      Presence.subscribe()
    end

    viewer_counts = Presence.get_viewer_counts()

    relays_bridge_id_to_metadata =
      for %{bridge_id: bridge_id, active_game: game_start, disconnected: disconnected} <- Streams.list_relays(), into: %{} do
        {bridge_id, %{active_game: game_start, disconnected: disconnected, viewer_count: Map.get(viewer_counts, bridge_id, 0)}}
      end

    {
      :ok,
      socket
      |> assign(:relays, relays_bridge_id_to_metadata)
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
      cond do
        !Map.has_key?(socket.assigns.relays, bridge_id) ->
          socket
          |> clear_watch()
          |> put_flash(:error, "Stream not found.")

        true ->
          assign(socket, :selected_bridge_id, bridge_id)
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_bridge_id, nil)}
  end

  @impl true
  def handle_info({:relay_created, bridge_id}, socket) do
    {:noreply,
     update(socket, :relays, fn old_relays ->
       Map.put(old_relays, bridge_id, %{active_game: nil, disconnected: false, viewer_count: 0})
     end)}
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

  def handle_info({:bridge_disconnected, bridge_id}, socket) do
    socket =
      if bridge_id == socket.assigns.selected_bridge_id do
        socket
        |> put_flash(:info, "Reconnecting to stream...")
      else
        socket
      end

    {
      :noreply,
      update(socket, :relays, fn relays ->
        put_in(relays[bridge_id].disconnected, true)
      end)
    }
  end

  def handle_info({:bridge_reconnected, bridge_id}, socket) do
    socket =
      if bridge_id == socket.assigns.selected_bridge_id do
        socket
        |> clear_flash()
      else
        socket
      end

    {:noreply, update(socket, :relays, fn relays -> put_in(relays[bridge_id].disconnected, false) end)}
  end

  def handle_info({:game_update, {bridge_id, maybe_event}}, socket) do
    {:noreply,
     update(socket, :relays, fn relays -> put_in(relays[bridge_id].active_game, maybe_event) end)}
  end

  def handle_info({SpectatorModeWeb.Presence, {:join, %{bridge_id: bridge_id}}}, socket) do
    {:noreply, update(socket, :relays, fn relays -> update_in(relays[bridge_id].viewer_count, fn v -> v + 1 end) end)}
  end

  def handle_info({SpectatorModeWeb.Presence, {:leave, %{bridge_id: bridge_id}}}, socket) do
    {:noreply, update(socket, :relays, fn relays -> update_in(relays[bridge_id].viewer_count, fn v -> v - 1 end) end)}
  end

  defp clear_watch(socket) do
    push_patch(socket, to: ~p"/")
  end
end
