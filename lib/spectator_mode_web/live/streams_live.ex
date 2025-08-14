defmodule SpectatorModeWeb.StreamsLive do
  use SpectatorModeWeb, :live_view

  alias SpectatorMode.Streams
  alias SpectatorModeWeb.Presence

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-row h-full">
      <div class={"w-full lg:w-96 flex-none h-full flex flex-col border-r border-gray-400 " <> if @selected_stream_id, do: "hidden lg:flex", else: ""}>
        <.link patch="/" class="text-center font-semibold text-xl italic py-2 border-b border-gray-400">
          SpectatorMode
        </.link>

        <div class="grow justify-start flex flex-col gap-4 overflow-y-auto bg-gray-100 p-4">
          <%= if map_size(@livestreams) == 0 do %>
            <p class="text-center">No current streams.</p>
          <% else %>
            <%= for {stream_id, %{active_game: active_game, viewer_count: viewer_count, disconnected: disconnected}} <- @livestreams do %>
              <button phx-click="watch" phx-value-streamid={stream_id}>
                <.stream_card
                  stream_id={stream_id}
                  active_game={active_game}
                  selected={stream_id == @selected_stream_id}
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
          <button :if={@selected_stream_id} phx-click="clear">
            <.icon name="hero-arrow-left-start-on-rectangle" class="h-5 w-5" />
            <span>Close stream</span>
          </button>
        </div>
        <div id="stream-id-target" streamid={@selected_stream_id} phx-hook="StreamIdHook"></div>
        <slippi-viewer id="viewer" zips-base-url="/assets" phx-update="ignore"></slippi-viewer>
        <div :if={!@selected_stream_id} class="text-center italic">
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
            </div>
          </:item>
          <:item title="Troubleshooting">
            <div>
              <p class="font-bold">The streaming client won't open/connect?</p>
              <ul class="list-disc">
                <li>
                  Check the troubleshooting instructions on the <.link
                    href="https://github.com/gcpreston/swb-rs/blob/main/README.md#troubleshooting"
                    target="_blank"
                    class="underline"
                  >repository's README</.link>.
                </li>
              </ul>
            </div>

            <div>
              <p class="mt-4 font-bold">The stream lags and jumps a lot?</p>
              <ul class="list-disc">
                <li>
                  This can happen with Chrome's energy saver mode, which limits the animation framerate.
                  It can be resolved by plugging in the device, or disabling energy saver mode in your browser settings.
                </li>
              </ul>
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

    # TODO: Get stream disconnected status on load
    #   Right now this is stored separately in BridgeRegistry. Not sure if this
    #   wants to be the case.
    #   Think about the individual console connections within the bridge. We
    #   will want to communicate from the bridge about the status of each of
    #   those, and do reconnections on them, etc (eventually).
    stream_id_to_metadata =
      for %{stream_id: stream_id, active_game: game_start} <- Streams.list_streams(), into: %{} do
        {stream_id, %{active_game: game_start, disconnected: false, viewer_count: Map.get(viewer_counts, stream_id, 0)}}
      end

    {
      :ok,
      socket
      |> assign(:livestreams, stream_id_to_metadata)
    }
  end

  @impl true
  def handle_event("watch", %{"streamid" => stream_id}, socket) do
    params = %{"watch" => stream_id}
    {:noreply, push_patch(socket, to: ~p"/?#{params}")}
  end

  def handle_event("clear", _params, socket) do
    {:noreply, clear_watch(socket)}
  end

  @impl true
  def handle_params(%{"watch" => stream_id}, _uri, socket) do
    stream_id = String.to_integer(stream_id)

    socket =
      cond do
        !Map.has_key?(socket.assigns.livestreams, stream_id) ->
          socket
          |> clear_watch()
          |> put_flash(:error, "Stream not found.")

        true ->
          assign(socket, :selected_stream_id, stream_id)
      end

    {:noreply, socket}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :selected_stream_id, nil)}
  end

  @impl true
  def handle_info({:livestream_created, stream_id}, socket) do
    {:noreply,
     update(socket, :livestreams, fn old_relays ->
       Map.put(old_relays, stream_id, %{active_game: nil, disconnected: false, viewer_count: 0})
     end)}
  end

  def handle_info({:livestream_destroyed, stream_id}, socket) do
    socket =
      if stream_id == socket.assigns.selected_stream_id do
        socket
        |> clear_watch()
        |> put_flash(:info, "This stream has ended.")
      else
        socket
      end

    {
      :noreply,
      update(socket, :livestreams, fn old_relays ->
        Map.delete(old_relays, stream_id)
      end)
    }
  end

  def handle_info({:streams_disconnected, stream_ids}, socket) do
    socket =
      if socket.assigns.selected_stream_id in stream_ids do
        socket
        |> put_flash(:info, "Stream source reconnecting...")
      else
        socket
      end

    {
      :noreply,
      update(socket, :livestreams, fn livestreams ->
        Enum.reduce(stream_ids, livestreams, fn stream_id, acc ->
          put_in(acc[stream_id].disconnected, true)
        end)
      end)
    }
  end

  def handle_info({:streams_reconnected, stream_ids}, socket) do
    socket =
      if socket.assigns.selected_stream_id in stream_ids do
        socket
        |> clear_flash()
      else
        socket
      end

    {
      :noreply,
      update(socket, :livestreams, fn livestreams ->
        Enum.reduce(stream_ids, livestreams, fn stream_id, acc ->
          put_in(acc[stream_id].disconnected, false)
        end)
      end)
    }
  end

  def handle_info({:game_update, {stream_id, maybe_event}}, socket) do
    {:noreply,
     update(socket, :livestreams, fn livestreams -> put_in(livestreams[stream_id].active_game, maybe_event) end)}
  end

  def handle_info({SpectatorModeWeb.Presence, {:join, %{stream_id: stream_id}}}, socket) do
    {:noreply, update(socket, :livestreams, fn livestreams -> update_in(livestreams[stream_id].viewer_count, fn v -> v + 1 end) end)}
  end

  def handle_info({SpectatorModeWeb.Presence, {:leave, %{stream_id: stream_id}}}, socket) do
    {
      :noreply,
      update(socket, :livestreams, fn livestreams ->
        if Map.has_key?(livestreams, stream_id) do
          update_in(livestreams[stream_id].viewer_count, fn v -> v - 1 end)
        else
          livestreams
        end
      end)
    }
  end

  defp clear_watch(socket) do
    push_patch(socket, to: ~p"/")
  end
end
