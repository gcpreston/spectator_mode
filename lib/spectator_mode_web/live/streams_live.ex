defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-row h-full">
      <div class={"w-full lg:w-96 flex-none h-full flex flex-col border-r border-gray-400 " <> if @selected_bridge_id, do: "hidden lg:flex", else: ""}>
        <div class="text-center font-semibold text-xl italic py-2 border-b border-gray-400">
          SpectatorMode
        </div>

        <div class="grow justify-start flex flex-col gap-4 overflow-y-auto bg-gray-100 p-4">
          <%= if map_size(@relays) == 0 do %>
            <p class="text-center">No current streams.</p>
          <% else %>
            <%= for {bridge_id, %{game_start: active_game, disconnected: disconnected}} <- @relays do %>
              <button phx-click="watch" phx-value-bridgeid={bridge_id}>
                <.stream_card
                  bridge_id={bridge_id}
                  active_game={active_game}
                  selected={bridge_id == @selected_bridge_id}
                  disconnected={disconnected}
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
                  <.link href="https://nodejs.org/en/download" target="_blank" class="underline">
                    Download and install NodeJS >= 22.4.0
                  </.link>
                </li>
                <li>Start Slippi Dolphin</li>
                <li>
                  In the terminal, run
                  <.code>npx @gcpreston/swb start</.code>
                </li>
                <li>The stream ID will be given in the terminal upon successful connection</li>
              </ul>
              <p class="mt-4">
                More information can be found in the <.link
                  href="https://www.npmjs.com/package/@gcpreston/swb"
                  target="_blank"
                  class="underline"
                >CLI package's README</.link>.
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
    end

    relays_bridge_id_to_metadata =
      for %{bridge_id: bridge_id, active_game: game_start} <- Streams.list_relays(), into: %{} do
        {bridge_id, %{game_start: game_start, disconnected: false}}
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
       Map.put(old_relays, bridge_id, %{game_start: nil, disconnected: false})
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

        # TODO: Actually try to reconnect
      else
        socket
      end

    {
      :noreply,
      update(socket, :relays, fn relays ->
        put_in(relays, [bridge_id, :disconnected], true)
      end)
    }
  end

  def handle_info({:game_update, {bridge_id, maybe_event}}, socket) do
    {:noreply,
     update(socket, :relays, fn old_relays -> Map.put(old_relays, bridge_id, maybe_event) end)}
  end

  defp clear_watch(socket) do
    push_patch(socket, to: ~p"/")
  end
end
